import Foundation

// MARK: - Results

public struct OperatingPoint: Sendable {
    /// Voltage of every node; index 0 (ground) is always 0.
    public var nodeVoltages: [Double]
    /// Main current of every netlist element (see `NetlistElement.branchNodes`): from pin 1 to
    /// pin 2 inside a two-terminal element, into an op-amp's output, into a BJT's collector (Ic),
    /// or into a MOSFET's drain (Id).
    public var elementCurrents: [Double]
    /// Voltage across each element's main current: pin 1 − pin 2, an op-amp's output voltage,
    /// a BJT's V_CE, or a MOSFET's V_DS.
    public var elementVoltages: [Double]
    /// Power absorbed by every element, over all its currents (a BJT's Ic·V_CE + Ib·V_BE).
    public var elementPowers: [Double]
}

public struct TransientResult: Sendable {
    public var time: [Double]
    /// `nodeVoltages[node][sample]`
    public var nodeVoltages: [[Double]]
    /// `elementCurrents[element][sample]`: each element's main current, as in `OperatingPoint`.
    public var elementCurrents: [[Double]]
}

public struct ACResult: Sendable {
    public var frequencies: [Double]
    /// `nodeVoltages[node][frequencyIndex]`
    public var nodeVoltages: [[Complex]]
    /// `elementCurrents[element][frequencyIndex]`
    public var elementCurrents: [[Complex]]
}

public enum SimulationOutput: Sendable {
    case operatingPoint(OperatingPoint)
    case transient(TransientResult)
    case ac(ACResult)
}

public struct SimulationResult: Sendable {
    public var netlist: Netlist
    public var settings: SimulationSettings
    public var output: SimulationOutput
}

public enum SimulationError: Error, LocalizedError, Equatable {
    case singular(unknown: String)
    case invalidSettings(String)
    case tooManyTimeSteps(Int)
    /// Newton–Raphson iteration on the diodes, transistors, and logic gates did not settle: at the DC solution when `time` is nil.
    case noConvergence(time: Double?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .singular(unknown):
            "The circuit equations cannot be solved (singular matrix near \(unknown)). "
                + "Check for loops made only of voltage sources and inductors (inductors are short circuits at DC), "
                + "or parts of the circuit that are not connected to ground."
        case let .invalidSettings(message):
            message
        case let .tooManyTimeSteps(count):
            "The transient analysis would need \(count) time steps. Increase the time step or shorten the stop time."
        case .noConvergence(time: nil):
            "The equations of the diodes, transistors, and logic gates did not converge to a DC solution. "
                + "Check for extreme component values, or devices connected with no consistent operating point, "
                + "such as a ring of an odd number of inverters, which can only oscillate."
        case let .noConvergence(time?):
            "The equations of the diodes, transistors, and logic gates did not converge at t = "
                + "\(SIFormat.string(time, unit: "s", significantDigits: 4)), even after splitting the time step. "
                + "Try a smaller time step."
        case .cancelled:
            "Simulation cancelled."
        }
    }
}

// MARK: - Simulator

/// Circuit simulator using Modified Nodal Analysis.
///
/// Unknowns are the non-ground node voltages followed by branch currents: one for each
/// voltage source, inductor, capacitor, diode, op-amp, MOSFET, and logic gate, and two (Ic, Ib) for each BJT.
/// Each two-terminal branch obeys `cv · (va − vb) + ci · i = rhs`, which lets every analysis
/// reuse the same stamp with different coefficients (see `branchEquation`). An op-amp is a
/// voltage source from its output to ground whose value is `A · (v+ − v−)`; its inputs draw no current.
///
/// Diodes, transistors, and logic gates make the equations nonlinear: each of their currents is a
/// function of a few control voltages (see `NonlinearModel`). DC and transient solutions then come
/// from Newton–Raphson iteration (see `newton`), which replaces each such current by its tangent
/// `Σⱼ Gⱼ · vⱼ − i = Σⱼ Gⱼ · vⱼ,ₖ − I(vₖ)` at the previous iterate vₖ. AC analysis uses the
/// tangent at the DC operating point. A logic gate's output follows its inputs one propagation delay
/// later, so in a transient analysis its current also depends on its inputs' recent past.
public enum Simulator {
    /// Conductance added from every node to ground so that nodes isolated at DC
    /// (e.g. between two capacitors) still have a defined voltage.
    public static let gmin = 1e-12
    public static let maxTimeSteps = 5_000_000
    /// Upper bound on stored transient samples; longer runs are decimated.
    public static let maxStoredSamples = 20_000

    /// Newton–Raphson convergence: successive iterates within `relativeTolerance` of each other,
    /// plus an absolute tolerance for voltages and for currents. SPICE's relative tolerance is 1e-3;
    /// circuits here are small, so a tighter one costs about one more iteration and matches hand
    /// calculations to the microvolt.
    static let relativeTolerance = 1e-6
    static let voltageTolerance = 1e-6
    static let currentTolerance = 1e-12
    static let maxOperatingPointIterations = 100
    static let maxStepIterations = 50
    /// A transient step that does not converge is split in halves, at most this many times over.
    static let maxStepSubdivisions = 10

    public static func run(_ circuit: Circuit) throws -> SimulationResult {
        let netlist = try Netlist(circuit: circuit)
        let settings = circuit.simulation
        let output: SimulationOutput
        switch settings.analysis {
        case .operatingPoint:
            output = .operatingPoint(try operatingPoint(netlist))
        case .transient:
            output = .transient(try transient(netlist, settings: settings))
        case .ac:
            output = .ac(try ac(netlist, settings: settings))
        }
        return SimulationResult(netlist: netlist, settings: settings, output: output)
    }

    // MARK: DC operating point

    public static func operatingPoint(_ netlist: Netlist, time: Double = 0) throws -> OperatingPoint {
        let layout = Layout(netlist)
        let x = try solveReal(netlist, layout: layout, mode: .dc, time: time, state: nil)
        var point = layout.operatingPoint(from: x, netlist: netlist, time: time)

        // Currents at the level of the gmin leakage are numerical noise (e.g. through a resistor
        // in series with a capacitor); report them as exactly zero.
        let maxVoltage = point.nodeVoltages.map(abs).max() ?? 0
        let noiseFloor = 10 * gmin * max(maxVoltage, 1) * Double(netlist.nodeCount)
        for (index, element) in netlist.elements.enumerated() where abs(point.elementCurrents[index]) < noiseFloor {
            point.elementCurrents[index] = 0
            point.elementPowers[index] = 0
            if element.kind == .resistor { point.elementVoltages[index] = 0 }
        }
        return point
    }

    // MARK: Transient

    /// Number of fixed steps and their size: the requested step, shrunk to divide the stop time evenly.
    static func timeSteps(_ settings: SimulationSettings) throws -> (count: Int, h: Double) {
        let stopTime = settings.stopTime
        guard stopTime.isFinite, stopTime > 0 else {
            throw SimulationError.invalidSettings("The stop time must be greater than zero.")
        }
        let requestedStep = settings.effectiveTimeStep
        guard requestedStep.isFinite, requestedStep > 0 else {
            throw SimulationError.invalidSettings("The time step must be greater than zero.")
        }
        let stepCountDouble = (stopTime / requestedStep).rounded(.up)
        guard stepCountDouble <= Double(maxTimeSteps) else {
            throw SimulationError.tooManyTimeSteps(Int(min(stepCountDouble, Double(Int.max / 2))))
        }
        let steps = max(1, Int(stepCountDouble))
        return (steps, stopTime / Double(steps))
    }

    public static func transient(_ netlist: Netlist, settings: SimulationSettings) throws -> TransientResult {
        let (steps, h) = try timeSteps(settings)
        let layout = Layout(netlist)

        // Initial solution at t = 0.
        let initialMode: Mode = settings.initialConditions == .zero ? .zeroInitialState : .dc
        let x0 = try solveReal(netlist, layout: layout, mode: initialMode, time: 0, state: nil)
        var state = layout.reactiveState(from: x0, netlist: netlist)
        var histories = gateHistories(netlist, layout: layout, from: x0, fromRest: settings.initialConditions == .zero)

        // Without nonlinear elements the matrix is constant for a fixed step, so factor it once.
        let mode: Mode = settings.integrationMethod == .trapezoidal ? .trapezoidal(h: h) : .backwardEuler(h: h)
        var lu: LUFactorization<Double>?
        if layout.nonlinear.isEmpty {
            do {
                lu = try LUFactorization(assembleMatrix(netlist, layout: layout, mode: mode))
            } catch let error as SingularMatrixError {
                throw SimulationError.singular(unknown: layout.unknownName(error.unknown, netlist: netlist))
            }
        }
        // Linear parts of the matrix for each depth of step splitting, when there are nonlinear elements.
        var matrices: [Int: DenseMatrix<Double>] = [:]

        let decimation = max(1, Int((Double(steps) / Double(maxStoredSamples)).rounded(.up)))
        let capacity = steps / decimation + 2
        var time: [Double] = []
        time.reserveCapacity(capacity)
        var voltages = Array(repeating: [Double](), count: netlist.nodeCount)
        var currents = Array(repeating: [Double](), count: netlist.elements.count)
        for i in voltages.indices { voltages[i].reserveCapacity(capacity) }
        for i in currents.indices { currents[i].reserveCapacity(capacity) }

        func record(_ x: [Double], at t: Double) {
            let point = layout.operatingPoint(from: x, netlist: netlist, time: t)
            time.append(t)
            for (i, v) in point.nodeVoltages.enumerated() { voltages[i].append(v) }
            for (i, c) in point.elementCurrents.enumerated() { currents[i].append(c) }
        }
        record(x0, at: 0)

        var previous = x0
        for step in 1...steps {
            if step % 4096 == 0, Task.isCancelled { throw SimulationError.cancelled }
            let t = Double(step) * h
            let x: [Double]
            if let lu {
                x = lu.solve(assembleRHS(netlist, layout: layout, mode: mode, time: t, state: state))
            } else {
                x = try nonlinearStep(
                    netlist, layout: layout, method: settings.integrationMethod,
                    from: previous, state: state, to: t, h: h, depth: 0, matrices: &matrices, histories: &histories)
            }
            previous = x
            state = layout.reactiveState(from: x, netlist: netlist)
            if step % decimation == 0 || step == steps {
                record(x, at: t)
            }
        }
        return TransientResult(time: time, nodeVoltages: voltages, elementCurrents: currents)
    }

    /// One transient step with nonlinear elements: Newton–Raphson from the previous solution `x`. A step that
    /// does not converge is replaced by two half steps (recursively, up to `maxStepSubdivisions`).
    /// Each solution found is recorded in the logic gates' `histories`.
    private static func nonlinearStep(
        _ netlist: Netlist, layout: Layout, method: SimulationSettings.IntegrationMethod,
        from x: [Double], state: ReactiveState, to t: Double, h: Double, depth: Int,
        matrices: inout [Int: DenseMatrix<Double>], histories: inout [Int: GateHistory]
    ) throws -> [Double] {
        let mode: Mode = method == .trapezoidal ? .trapezoidal(h: h) : .backwardEuler(h: h)
        let matrix = matrices[depth] ?? assembleMatrix(netlist, layout: layout, mode: mode)
        matrices[depth] = matrix
        let rhs = assembleRHS(netlist, layout: layout, mode: mode, time: t, state: state)
        let models = nonlinearModels(netlist, layout: layout, mode: mode, time: t, histories: histories)
        if let next = try newton(netlist, layout: layout, models: models, matrix: matrix, rhs: rhs, guess: x, maxIterations: maxStepIterations) {
            recordTargets(next, at: t, netlist: netlist, layout: layout, histories: &histories)
            return next
        }
        guard depth < maxStepSubdivisions else { throw SimulationError.noConvergence(time: t) }
        let middle = try nonlinearStep(
            netlist, layout: layout, method: method, from: x, state: state,
            to: t - h / 2, h: h / 2, depth: depth + 1, matrices: &matrices, histories: &histories)
        return try nonlinearStep(
            netlist, layout: layout, method: method, from: middle, state: layout.reactiveState(from: middle, netlist: netlist),
            to: t, h: h / 2, depth: depth + 1, matrices: &matrices, histories: &histories)
    }

    /// The target of each logic gate (see `LogicGateModel`) at the solution `x0` at t = 0, as the
    /// start of its history. Before t = 0, a gate starting from rest was at 0 V, and one starting
    /// from the DC operating point was at its target.
    static func gateHistories(_ netlist: Netlist, layout: Layout, from x0: [Double], fromRest: Bool) -> [Int: GateHistory] {
        var histories: [Int: GateHistory] = [:]
        for index in layout.nonlinear where netlist.elements[index].kind == .logicGate {
            let element = netlist.elements[index]
            let target = element.gate.target(element.inputNodes.map { layout.voltage(x0, $0) }).voltage
            histories[index] = GateHistory(initial: fromRest ? 0 : target)
        }
        recordTargets(x0, at: 0, netlist: netlist, layout: layout, histories: &histories)
        return histories
    }

    /// Records each logic gate's target at the solution `x` at time `t`.
    static func recordTargets(_ x: [Double], at t: Double, netlist: Netlist, layout: Layout, histories: inout [Int: GateHistory]) {
        for index in histories.keys {
            let element = netlist.elements[index]
            let target = element.gate.target(element.inputNodes.map { layout.voltage(x, $0) }).voltage
            histories[index]!.record(target, at: t, delay: element.gate.delay)
        }
    }

    // MARK: AC sweep

    public static func ac(_ netlist: Netlist, settings: SimulationSettings) throws -> ACResult {
        let start = settings.startFrequency, stop = settings.stopFrequency
        guard start.isFinite, stop.isFinite, start > 0, stop > start else {
            throw SimulationError.invalidSettings("The AC sweep needs 0 < start frequency < stop frequency.")
        }
        guard settings.pointsPerDecade >= 1 else {
            throw SimulationError.invalidSettings("Points per decade must be at least 1.")
        }
        let decades = log10(stop / start)
        let count = min(100_000, max(2, Int((decades * Double(settings.pointsPerDecade)).rounded(.up)) + 1))
        let frequencies = (0..<count).map { start * pow(10, decades * Double($0) / Double(count - 1)) }

        let layout = Layout(netlist)
        var voltages = Array(repeating: [Complex](), count: netlist.nodeCount)
        var currents = Array(repeating: [Complex](), count: netlist.elements.count)

        // Nonlinear elements act as their tangent (small-signal model) at the DC operating point.
        var slopes: [Int: [[Double]]] = [:]
        if !layout.nonlinear.isEmpty {
            let point = try operatingPoint(netlist)
            for index in layout.nonlinear {
                let element = netlist.elements[index]
                let controls = element.controlNodes.map { point.nodeVoltages[$0.0] - point.nodeVoltages[$0.1] }
                slopes[index] = element.nonlinearModel!.linearize(at: controls).jacobian
            }
        }

        for f in frequencies {
            if Task.isCancelled { throw SimulationError.cancelled }
            let (matrix, rhs) = assembleAC(netlist, layout: layout, omega: 2 * Double.pi * f, slopes: slopes)
            let x: [Complex]
            do {
                x = try LUFactorization(matrix).solve(rhs)
            } catch let error as SingularMatrixError {
                throw SimulationError.singular(unknown: layout.unknownName(error.unknown, netlist: netlist))
            }

            voltages[0].append(.zero)
            for node in 1..<netlist.nodeCount { voltages[node].append(x[node - 1]) }
            for (index, element) in netlist.elements.enumerated() {
                let va = element.nodeA == 0 ? Complex.zero : x[element.nodeA - 1]
                let vb = element.nodeB == 0 ? Complex.zero : x[element.nodeB - 1]
                let current: Complex = switch element.kind {
                case .resistor: (va - vb) / Complex(element.value)
                case .currentSource: Complex(magnitude: element.waveform.acMagnitude, phase: element.waveform.acPhase * .pi / 180)
                default: layout.branch[index].map { x[$0] } ?? .zero
                }
                currents[index].append(current)
            }
        }
        return ACResult(frequencies: frequencies, nodeVoltages: voltages, elementCurrents: currents)
    }

    /// The phasor system at angular frequency `omega`. `slopes[element]` holds the small-signal
    /// slopes ∂I/∂V of each nonlinear element (in `NonlinearModel` order); missing ones are zero.
    static func assembleAC(
        _ netlist: Netlist, layout: Layout, omega: Double, slopes: [Int: [[Double]]]
    ) -> (matrix: DenseMatrix<Complex>, rhs: [Complex]) {
        var matrix = DenseMatrix<Complex>(size: layout.size)
        var rhs = Array(repeating: Complex.zero, count: layout.size)
        for i in 0..<(netlist.nodeCount - 1) { matrix[i, i] += Complex(gmin) }

        for (index, element) in netlist.elements.enumerated() {
            let a = layout.row(element.nodeA), b = layout.row(element.nodeB)
            let source = Complex(
                magnitude: element.waveform.acMagnitude,
                phase: element.waveform.acPhase * .pi / 180)
            switch element.kind {
            case .resistor:
                matrix.stampConductance(a, b, Complex(1 / element.value))
            case .currentSource:
                if let a { rhs[a] -= source }
                if let b { rhs[b] += source }
            case .voltageSource:
                let k = layout.branch[index]!
                matrix.stampBranch(a, b, k, cv: .one, ci: .zero)
                rhs[k] = source
            case .inductor:
                let k = layout.branch[index]!
                matrix.stampBranch(a, b, k, cv: .one, ci: Complex(0, -omega * element.value))
            case .capacitor:
                let k = layout.branch[index]!
                matrix.stampBranch(a, b, k, cv: Complex(0, omega * element.value), ci: Complex(-1))
            case .diode, .bjt, .mosfet:
                matrix.stampNonlinear(element, layout: layout, branch: layout.branch[index]!, slopes: slopes[index].map {
                    $0.map { $0.map { Complex($0) } }
                })
            case .logicGate:
                // The propagation delay shifts the inputs' effect in phase by e^(−jω·t_pd).
                let lag = Complex(magnitude: 1, phase: -omega * element.gate.delay)
                matrix.stampNonlinear(element, layout: layout, branch: layout.branch[index]!, slopes: slopes[index].map {
                    $0.map { row in row.enumerated().map { j, slope in j == 0 ? Complex(slope) : Complex(slope) * lag } }
                })
            case .opAmp:
                matrix.stampOpAmp(a, b, layout.row(element.outputNode), layout.branch[index]!, gain: Complex(element.value))
            case .ground, .netLabel:
                break
            }
        }
        return (matrix, rhs)
    }

    // MARK: - Real-valued assembly (DC and transient)

    enum Mode {
        /// Capacitors open, inductors shorted.
        case dc
        /// Capacitors held at 0 V, inductors at 0 A (used for the t = 0 solution).
        case zeroInitialState
        case backwardEuler(h: Double)
        case trapezoidal(h: Double)
    }

    /// Voltage across and current through each capacitor and inductor at the previous time point.
    struct ReactiveState {
        var voltage: [Double]
        var current: [Double]
    }

    /// Coefficients of a branch equation `cv · (va − vb) + ci · i = rhs`.
    private static func branchEquation(
        for element: NetlistElement, index: Int, mode: Mode, time: Double, state: ReactiveState?
    ) -> (cv: Double, ci: Double, rhs: Double) {
        let vPrev = state?.voltage[index] ?? 0
        let iPrev = state?.current[index] ?? 0
        switch element.kind {
        case .voltageSource:
            return (1, 0, element.waveform.value(at: time, level: element.value))
        case .inductor:
            let l = element.value
            switch mode {
            case .dc: return (1, 0, 0)
            case .zeroInitialState: return (0, 1, 0)
            case let .backwardEuler(h): return (1, -l / h, -(l / h) * iPrev)
            case let .trapezoidal(h): return (1, -2 * l / h, -(2 * l / h) * iPrev - vPrev)
            }
        case .capacitor:
            let c = element.value
            switch mode {
            case .dc: return (0, 1, 0)
            case .zeroInitialState: return (1, 0, 0)
            case let .backwardEuler(h): return (c / h, -1, (c / h) * vPrev)
            case let .trapezoidal(h): return (2 * c / h, -1, (2 * c / h) * vPrev + iPrev)
            }
        default:
            return (0, 0, 0)
        }
    }

    static func assembleMatrix(_ netlist: Netlist, layout: Layout, mode: Mode) -> DenseMatrix<Double> {
        var matrix = DenseMatrix<Double>(size: layout.size)
        for i in 0..<(netlist.nodeCount - 1) { matrix[i, i] += gmin }
        for (index, element) in netlist.elements.enumerated() {
            let a = layout.row(element.nodeA), b = layout.row(element.nodeB)
            if element.kind == .resistor {
                matrix.stampConductance(a, b, 1 / element.value)
            } else if element.kind == .opAmp {
                matrix.stampOpAmp(a, b, layout.row(element.outputNode), layout.branch[index]!, gain: element.value)
            } else if element.nonlinearModel != nil {
                // The linear part only: `newton` adds the tangent.
                matrix.stampNonlinear(element, layout: layout, branch: layout.branch[index]!, slopes: nil)
            } else if let k = layout.branch[index] {
                let eq = branchEquation(for: element, index: index, mode: mode, time: 0, state: nil)
                matrix.stampBranch(a, b, k, cv: eq.cv, ci: eq.ci)
            }
        }
        return matrix
    }

    private static func assembleRHS(
        _ netlist: Netlist, layout: Layout, mode: Mode, time: Double, state: ReactiveState?
    ) -> [Double] {
        var rhs = Array(repeating: 0.0, count: layout.size)
        for (index, element) in netlist.elements.enumerated() {
            if element.kind == .currentSource {
                let current = element.waveform.value(at: time, level: element.value)
                if let a = layout.row(element.nodeA) { rhs[a] -= current }
                if let b = layout.row(element.nodeB) { rhs[b] += current }
            } else if let k = layout.branch[index] {
                rhs[k] = branchEquation(for: element, index: index, mode: mode, time: time, state: state).rhs
            }
        }
        return rhs
    }

    private static func solveReal(
        _ netlist: Netlist, layout: Layout, mode: Mode, time: Double, state: ReactiveState?
    ) throws -> [Double] {
        let matrix = assembleMatrix(netlist, layout: layout, mode: mode)
        let rhs = assembleRHS(netlist, layout: layout, mode: mode, time: time, state: state)
        if !layout.nonlinear.isEmpty {
            let models = nonlinearModels(netlist, layout: layout, mode: mode, time: time, histories: nil)
            return try solveNonlinear(netlist, layout: layout, models: models, matrix: matrix, rhs: rhs)
        }
        do {
            return try LUFactorization(matrix).solve(rhs)
        } catch let error as SingularMatrixError {
            throw SimulationError.singular(unknown: layout.unknownName(error.unknown, netlist: netlist))
        }
    }

    // MARK: - Newton–Raphson (diodes, transistors, and logic gates)

    /// The model of each nonlinear element, in `layout.nonlinear` order, for a solution at `time` in
    /// `mode`. A logic gate's output drives toward its target one propagation delay ago (see
    /// `LogicGateModel`): at DC the target now; from rest, 0 V; and in a time step of h, the target
    /// recorded in its history at `time` − t_pd. When the delay is shorter than the step, that time
    /// falls inside the step, between the previous time point and the present one, whose target
    /// depends on the unknown inputs.
    static func nonlinearModels(
        _ netlist: Netlist, layout: Layout, mode: Mode, time: Double, histories: [Int: GateHistory]?
    ) -> [any NonlinearModel] {
        layout.nonlinear.map { index in
            let element = netlist.elements[index]
            guard element.kind == .logicGate else { return element.nonlinearModel! }
            let gate = element.gate
            switch mode {
            case .dc:
                return gate.step(hold: 0, drive: 1)
            case .zeroInitialState:
                return gate.step(hold: 0, drive: gate.delay > 0 ? 0 : 1)
            case let .backwardEuler(h), let .trapezoidal(h):
                let history = histories?[index] ?? GateHistory(initial: 0)
                if gate.delay >= h { return gate.step(hold: history.target(at: time - gate.delay), drive: 0) }
                let fraction = gate.delay / h
                return gate.step(hold: fraction * history.target(at: time - h), drive: 1 - fraction)
            }
        }
    }

    /// A DC-like solution with nonlinear elements: Newton–Raphson from zero. If that does not settle, the sources
    /// are ramped up from zero instead (source stepping), each solution the start of the next.
    /// The right-hand side holds only source values here, so scaling it scales the sources.
    private static func solveNonlinear(
        _ netlist: Netlist, layout: Layout, models: [any NonlinearModel], matrix: DenseMatrix<Double>, rhs: [Double]
    ) throws -> [Double] {
        let zero = Array(repeating: 0.0, count: layout.size)
        if let x = try newton(netlist, layout: layout, models: models, matrix: matrix, rhs: rhs, guess: zero, maxIterations: maxOperatingPointIterations) {
            return x
        }
        var x = zero, scale = 0.0, increment = 0.1
        while scale < 1 {
            let target = min(1, scale + increment)
            let scaled = rhs.map { $0 * target }
            if let next = try newton(netlist, layout: layout, models: models, matrix: matrix, rhs: scaled, guess: x, maxIterations: maxOperatingPointIterations) {
                x = next
                scale = target
                increment = min(2 * increment, 0.25)
            } else {
                increment /= 4
                guard increment > 1e-6 else { throw SimulationError.noConvergence(time: nil) }
            }
        }
        return x
    }

    /// Solves the system whose linear part is `matrix`·x = `rhs`, with each nonlinear current replaced
    /// by its tangent at the previous iterate, until successive iterates agree. `models` are the
    /// nonlinear elements' models (see `nonlinearModels`). Returns nil if the iterates do not agree
    /// within `maxIterations`.
    static func newton(
        _ netlist: Netlist, layout: Layout, models: [any NonlinearModel], matrix: DenseMatrix<Double>, rhs: [Double],
        guess: [Double], maxIterations: Int
    ) throws -> [Double]? {
        let devices = zip(layout.nonlinear, models).map { index, model in
            (element: netlist.elements[index], model: model, branch: layout.branch[index]!)
        }
        func controls(_ x: [Double], _ element: NetlistElement) -> [Double] {
            element.controlNodes.map { layout.voltage(x, $0.0) - layout.voltage(x, $0.1) }
        }
        var x = guess
        // Each device's control voltages at the previous iterate, after step limiting, and its tangent there.
        var operating = devices.map { controls(x, $0.element) }
        var tangents = zip(devices, operating).map { device, v in device.model.linearize(at: v) }

        for _ in 0..<maxIterations {
            var a = matrix, b = rhs
            for (d, device) in devices.enumerated() {
                let (currents, jacobian) = tangents[d]
                for (i, current) in currents.enumerated() {
                    let k = device.branch + i
                    var offset = -current
                    for (j, nodes) in device.element.controlNodes.enumerated() {
                        let slope = jacobian[i][j]
                        a.add(k, layout.row(nodes.0), slope)
                        a.add(k, layout.row(nodes.1), -slope)
                        offset += slope * operating[d][j]
                    }
                    b[k] += offset
                }
            }
            let next: [Double]
            do {
                next = try LUFactorization(a).solve(b)
            } catch let error as SingularMatrixError {
                throw SimulationError.singular(unknown: layout.unknownName(error.unknown, netlist: netlist))
            }

            var settled = next.indices.allSatisfy { i in
                let tolerance = i < layout.nodeCount - 1 ? voltageTolerance : currentTolerance
                return abs(next[i] - x[i]) <= relativeTolerance * max(abs(next[i]), abs(x[i])) + tolerance
            }
            for (d, device) in devices.enumerated() {
                let v = controls(next, device.element)
                let limited = device.model.limitStep(v, from: operating[d])
                operating[d] = limited
                tangents[d] = device.model.linearize(at: limited)
                if limited != v { settled = false }
                // The solved currents lie on the tangents; they must also lie on the device's curves.
                for (i, exact) in tangents[d].currents.enumerated() {
                    let solved = next[device.branch + i]
                    if abs(solved - exact) > relativeTolerance * max(abs(solved), abs(exact)) + currentTolerance {
                        settled = false
                    }
                }
            }
            x = next
            if settled { return x }
        }
        return nil
    }

    // MARK: - Unknown layout

    struct Layout {
        let nodeCount: Int
        /// Row/column of each element's first branch current, if it has any. A BJT's base current
        /// follows its collector current.
        let branch: [Int?]
        let size: Int
        /// Indices of the nonlinear elements (diodes, transistors, and logic gates) among the netlist elements.
        let nonlinear: [Int]

        init(_ netlist: Netlist) {
            nodeCount = netlist.nodeCount
            var next = netlist.nodeCount - 1
            branch = netlist.elements.map { element in
                guard element.branchCount > 0 else { return nil }
                defer { next += element.branchCount }
                return next
            }
            size = next
            nonlinear = netlist.elements.indices.filter { netlist.elements[$0].nonlinearModel != nil }
        }

        func row(_ node: Int) -> Int? { node == 0 ? nil : node - 1 }

        func unknownName(_ index: Int, netlist: Netlist) -> String {
            if index < nodeCount - 1 { return "V(\(netlist.nodeNames[index + 1]))" }
            for (element, first) in branch.enumerated() {
                guard let first, index >= first, index < first + netlist.elements[element].branchCount else { continue }
                return netlist.elements[element].currentNames[index - first]
            }
            return "unknown \(index)"
        }

        func voltage(_ x: [Double], _ node: Int) -> Double { node == 0 ? 0 : x[node - 1] }

        func operatingPoint(from x: [Double], netlist: Netlist, time: Double) -> OperatingPoint {
            var voltages = Array(repeating: 0.0, count: nodeCount)
            for node in 1..<max(1, nodeCount) { voltages[node] = x[node - 1] }
            let elementVoltages = netlist.elements.map { element in
                voltage(x, element.branchNodes[0].from) - voltage(x, element.branchNodes[0].to)
            }
            let currents = netlist.elements.enumerated().map { index, element -> Double in
                switch element.kind {
                case .resistor:
                    elementVoltages[index] / element.value
                case .currentSource:
                    element.waveform.value(at: time, level: element.value)
                default:
                    branch[index].map { x[$0] } ?? 0
                }
            }
            // Power over every current of the element; only a BJT has a second one, its base current.
            let powers = netlist.elements.enumerated().map { index, element in
                element.branchNodes.enumerated().reduce(0.0) { sum, pair in
                    let (i, nodes) = pair
                    let current = i == 0 ? currents[index] : x[branch[index]! + i]
                    return sum + current * (voltage(x, nodes.from) - voltage(x, nodes.to))
                }
            }
            return OperatingPoint(nodeVoltages: voltages, elementCurrents: currents, elementVoltages: elementVoltages, elementPowers: powers)
        }

        func reactiveState(from x: [Double], netlist: Netlist) -> ReactiveState {
            var state = ReactiveState(
                voltage: Array(repeating: 0, count: netlist.elements.count),
                current: Array(repeating: 0, count: netlist.elements.count))
            for (index, element) in netlist.elements.enumerated() where element.kind == .capacitor || element.kind == .inductor {
                guard let k = branch[index] else { continue }
                state.voltage[index] = voltage(x, element.nodeA) - voltage(x, element.nodeB)
                state.current[index] = x[k]
            }
            return state
        }
    }
}

// MARK: - Stamps

extension DenseMatrix {
    /// Conductance `g` between rows `a` and `b` (either may be ground).
    mutating func stampConductance(_ a: Int?, _ b: Int?, _ g: T) {
        add(a, a, g)
        add(b, b, g)
        add(a, b, -g)
        add(b, a, -g)
    }

    /// Branch current `k` flowing a → b inside the element, with branch equation
    /// `cv · (va − vb) + ci · i = rhs`.
    mutating func stampBranch(_ a: Int?, _ b: Int?, _ k: Int, cv: T, ci: T) {
        add(a, k, T.one)
        add(b, k, -T.one)
        add(k, a, cv)
        add(k, b, -cv)
        add(k, k, ci)
    }

    /// The currents of a nonlinear element: each flows inside it along `branchNodes` with branch
    /// row `branch + i`, and its row is `Σⱼ slopes[i][j] · vⱼ − i = …` over the control voltages vⱼ.
    /// Without slopes, only the linear part (−i) is stamped.
    mutating func stampNonlinear(_ element: NetlistElement, layout: Simulator.Layout, branch: Int, slopes: [[T]]?) {
        for (i, nodes) in element.branchNodes.enumerated() {
            let k = branch + i
            stampBranch(layout.row(nodes.from), layout.row(nodes.to), k, cv: T.zero, ci: -T.one)
            guard let slopes else { continue }
            for (j, control) in element.controlNodes.enumerated() {
                add(k, layout.row(control.0), slopes[i][j])
                add(k, layout.row(control.1), -slopes[i][j])
            }
        }
    }

    /// An op-amp with inputs `plus` and `minus` and output `out`: branch current `k` flows into
    /// the output and down to ground, with branch equation `vout − gain · (v+ − v−) = 0`.
    /// The inputs draw no current.
    mutating func stampOpAmp(_ plus: Int?, _ minus: Int?, _ out: Int?, _ k: Int, gain: T) {
        add(out, k, T.one)
        add(k, out, T.one)
        add(k, plus, -gain)
        add(k, minus, gain)
    }
}
