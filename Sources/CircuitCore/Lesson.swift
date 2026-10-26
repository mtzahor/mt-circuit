import Foundation

// MARK: - Lessons

/// One step of the tutorial: an explanation of a concept, then a challenge whose goals are
/// checked by simulating the learner's circuit.
public struct Lesson: Identifiable, Sendable {
    public var id: String
    public var chapter: String
    public var title: String
    /// The concept, in paragraphs separated by blank lines, with Markdown emphasis. A paragraph
    /// that starts with "> " is a formula.
    public var introduction: String
    /// What to build or change, in the same format as `introduction`.
    public var challenge: String
    public var goals: [Goal]
    /// Increasingly specific hints, revealed one at a time.
    public var hints: [String]
    /// The worked answer.
    public var answer: String
    /// The circuit the lesson starts from. It meets some goals but not all.
    public var starter: Circuit
    /// A circuit that meets every goal.
    public var solution: Circuit

    /// The starter circuit, tagged with the lesson so that its document opens in the tutorial.
    public var startingCircuit: Circuit { tagged(starter) }
    /// The solution, tagged with the lesson.
    public var solvedCircuit: Circuit { tagged(solution) }

    private func tagged(_ circuit: Circuit) -> Circuit {
        var circuit = circuit
        circuit.lesson = id
        return circuit
    }

    /// Checks every goal on `circuit`. Each analysis the goals need runs once, with the goal's
    /// settings rather than the circuit's own.
    public func evaluate(_ circuit: Circuit) -> [GoalStatus] {
        var results: [SimulationSettings: Result<SimulationResult, any Error>] = [:]
        var statuses: [GoalStatus] = []
        for goal in goals {
            guard let settings = goal.analysis else {
                statuses.append(goal.check(circuit, nil))
                continue
            }
            let outcome: Result<SimulationResult, any Error>
            if let cached = results[settings] {
                outcome = cached
            } else {
                var copy = circuit
                copy.simulation = settings
                outcome = Result { try Simulator.run(copy) }
                results[settings] = outcome
            }
            switch outcome {
            case let .success(result):
                statuses.append(goal.check(circuit, result))
            case let .failure(error):
                statuses.append(.unavailable(error.localizedDescription))
            }
        }
        return statuses
    }
}

// MARK: - Goals

/// Whether a goal is met, with what was measured or why it could not be.
public enum GoalStatus: Sendable, Hashable {
    case met(String)
    case notMet(String)
    /// The goal could not be measured: the circuit does not simulate, or lacks the net or part
    /// the goal names.
    case unavailable(String)

    public var isMet: Bool {
        if case .met = self { return true }
        return false
    }

    /// The measured value ("Now: 2.5 V") or the reason it is unknown; may be empty.
    public var detail: String {
        switch self {
        case let .met(detail), let .notMet(detail), let .unavailable(detail): detail
        }
    }
}

/// A bound on a measured quantity.
public enum Requirement: Sendable, Hashable {
    /// Within a relative tolerance of a target, e.g. 0.01 for ± 1 %.
    case near(Double, tolerance: Double)
    case atLeast(Double)
    case atMost(Double)

    public func isMet(by value: Double) -> Bool {
        switch self {
        case let .near(target, tolerance): abs(value - target) <= tolerance * abs(target)
        case let .atLeast(bound): value >= bound
        case let .atMost(bound): value <= bound
        }
    }

    /// "= 3.3 V ± 1 %", "≥ 20 mA", or "≤ 250 mW".
    public func description(unit: String) -> String {
        switch self {
        case let .near(target, tolerance):
            "= \(SIFormat.string(target, unit: unit)) ± \(String(format: "%g", tolerance * 100)) %"
        case let .atLeast(bound): "≥ \(SIFormat.string(bound, unit: unit))"
        case let .atMost(bound): "≤ \(SIFormat.string(bound, unit: unit))"
        }
    }
}

/// Something a lesson's circuit must achieve, such as "V(out) = 3.3 V ± 1 %".
public struct Goal: Sendable {
    public var title: String
    /// The analysis the goal is measured with, whatever the circuit's own settings; nil for a
    /// goal about the schematic itself.
    public var analysis: SimulationSettings?
    /// Measures the goal on the circuit and the result of `analysis` (nil when `analysis` is).
    let check: @Sendable (Circuit, SimulationResult?) -> GoalStatus

    public enum Filter: Sendable {
        case lowPass, highPass
    }

    // MARK: Schematic

    /// The schematic has at least one part of `kind`.
    public static func places(_ kind: ComponentKind, _ title: String) -> Goal {
        Goal(title: title, analysis: nil) { circuit, _ in
            circuit.components.contains { $0.kind == kind } ? .met("") : .notMet("")
        }
    }

    /// There is at least one part of `kind`, and every one has `value`: "Use only 1 kΩ resistors".
    public static func onlyUses(_ kind: ComponentKind, value: Double) -> Goal {
        let unit = kind.unitSymbol
        let title = "Use only \(SIFormat.string(value, unit: unit)) \(kind.displayName.lowercased())s"
        return Goal(title: title, analysis: nil) { circuit, _ in
            let parts = circuit.components.filter { $0.kind == kind }
            guard !parts.isEmpty else { return .notMet("There are none yet.") }
            if let odd = parts.first(where: { !Self.equal($0.value, value) }) {
                return .notMet("\(odd.name) is \(SIFormat.string(odd.value, unit: unit, significantDigits: 4)).")
            }
            return .met("")
        }
    }

    /// The part named `name` still has its starting `value`, so the challenge can't be met by
    /// changing the wrong part.
    public static func keeps(_ name: String, at value: Double, unit: String) -> Goal {
        Goal(title: "Keep \(name) at \(SIFormat.string(value, unit: unit))", analysis: nil) { circuit, _ in
            guard let part = circuit.components.first(where: { $0.name == name }) else {
                return .notMet("There is no \(name).")
            }
            if Self.equal(part.value, value) { return .met("") }
            return .notMet("Now: \(SIFormat.string(part.value, unit: unit, significantDigits: 4))")
        }
    }

    private static func equal(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(abs(a), abs(b))
    }

    // MARK: DC operating point

    /// The DC voltage of the net labeled `net`.
    public static func voltage(_ net: String, _ requirement: Requirement) -> Goal {
        measuring("V(\(net))", unit: "V", requirement, analysis: .dc) { _, result in
            try result.operatingPoint().nodeVoltages[result.node(net)]
        }
    }

    /// The magnitude of the DC current through `element` (its main current: Ic of a BJT, Id of a MOSFET).
    public static func current(_ element: String, _ requirement: Requirement, quantity: String? = nil) -> Goal {
        measuring(quantity ?? "Current through \(element)", unit: "A", requirement, analysis: .dc) { circuit, result in
            abs(try result.operatingPoint().elementCurrents[result.element(element, in: circuit)])
        }
    }

    /// The DC power absorbed by `element`.
    public static func power(_ element: String, _ requirement: Requirement) -> Goal {
        measuring("Power in \(element)", unit: "W", requirement, analysis: .dc) { circuit, result in
            try result.operatingPoint().elementPowers[result.element(element, in: circuit)]
        }
    }

    /// A BJT's operating region at the DC operating point.
    public static func region(_ transistor: String, _ region: BJTModel.Region) -> Goal {
        let phrase = region == .active ? "the forward-active region" : region.rawValue
        return regionGoal("\(transistor) is in \(phrase)", transistor, kind: .bjt) { element, v in
            // Pins: collector 0, base 1, emitter 2.
            let now = element.bjt.region(vbe: v(1) - v(2), vbc: v(1) - v(0))
            return (now == region, now.rawValue)
        }
    }

    /// A MOSFET's operating region at the DC operating point.
    public static func region(_ transistor: String, _ region: MOSFETModel.Region) -> Goal {
        regionGoal("\(transistor) is in \(region.rawValue)", transistor, kind: .mosfet) { element, v in
            // Pins: drain 0, gate 1, source 2.
            let now = element.mosfet.region(vgs: v(1) - v(2), vds: v(0) - v(2))
            return (now == region, now.rawValue)
        }
    }

    /// `classify` gets the element and the voltage of each of its pins, and returns whether the
    /// region is the wanted one and the region's name.
    private static func regionGoal(
        _ title: String, _ name: String, kind: ComponentKind,
        _ classify: @escaping @Sendable (NetlistElement, (Int) -> Double) -> (Bool, String)
    ) -> Goal {
        Goal(title: title, analysis: .dc) { circuit, result in
            Self.status {
                let result = result!
                let op = try result.operatingPoint()
                let element = result.netlist.elements[try result.element(name, in: circuit)]
                guard element.kind == kind else { throw Unmeasurable.missing("\(name) is not a \(kind.displayName).") }
                let (met, now) = classify(element) { op.nodeVoltages[element.nodes[$0]] }
                return met ? .met("Now: \(now)") : .notMet("Now: \(now)")
            }
        }
    }

    // MARK: Transient

    /// The voltage of the net labeled `net` at `time`, in a transient analysis from rest.
    public static func voltage(_ net: String, at time: Double, _ requirement: Requirement, stopTime: Double) -> Goal {
        let quantity = "V(\(net)) at t = \(SIFormat.string(time, unit: "s"))"
        return measuring(quantity, unit: "V", requirement, analysis: .transient(stopTime: stopTime)) { _, result in
            let transient = try result.transient()
            return transient.nodeVoltages[try result.node(net)].interpolated(at: time, over: transient.time)
        }
    }

    /// The magnitude of the current through `element` at `time`, in a transient analysis from rest.
    public static func current(_ element: String, at time: Double, _ requirement: Requirement, stopTime: Double) -> Goal {
        let quantity = "Current through \(element) at t = \(SIFormat.string(time, unit: "s"))"
        return measuring(quantity, unit: "A", requirement, analysis: .transient(stopTime: stopTime)) { circuit, result in
            let transient = try result.transient()
            let index = try result.element(element, in: circuit)
            return abs(transient.elementCurrents[index].interpolated(at: time, over: transient.time))
        }
    }

    /// The peak-to-peak variation of the net labeled `net` from `start` to the end of a transient
    /// analysis from rest.
    public static func ripple(_ net: String, after start: Double, _ requirement: Requirement, stopTime: Double) -> Goal {
        measuring("Ripple on V(\(net))", unit: "V", requirement, analysis: .transient(stopTime: stopTime)) { _, result in
            let transient = try result.transient()
            let voltages = transient.nodeVoltages[try result.node(net)]
            let window = zip(transient.time, voltages).filter { $0.0 >= start }.map(\.1)
            return (window.max() ?? 0) - (window.min() ?? 0)
        }
    }

    // MARK: AC sweep

    /// The −3 dB frequency of the net labeled `net`: where a low-pass filter falls to 1/√2 of its
    /// level at the lowest frequency of `sweep`, or a high-pass filter to 1/√2 of its level at the highest.
    public static func cutoff(_ net: String, _ filter: Filter, _ requirement: Requirement, sweep: ClosedRange<Double>) -> Goal {
        measuring("Cutoff frequency of V(\(net))", unit: "Hz", requirement, analysis: .ac(sweep, pointsPerDecade: 100)) { _, result in
            let ac = try result.ac()
            let magnitudes = ac.nodeVoltages[try result.node(net)].map(\.magnitude)
            return try cutoffFrequency(magnitudes, ac.frequencies, filter, net: net)
        }
    }

    /// The frequency at which the net labeled `net` peaks, within `sweep`.
    public static func peak(_ net: String, _ requirement: Requirement, sweep: ClosedRange<Double>) -> Goal {
        measuring("Peak frequency of V(\(net))", unit: "Hz", requirement, analysis: .ac(sweep, pointsPerDecade: 200)) { _, result in
            let ac = try result.ac()
            let magnitudes = ac.nodeVoltages[try result.node(net)].map(\.magnitude)
            return try peakFrequency(magnitudes, ac.frequencies, net: net)
        }
    }

    /// The signed voltage gain V(output) / V(input) at `frequency`: negative when the output is inverted.
    public static func gain(_ output: String, over input: String, at frequency: Double, _ requirement: Requirement) -> Goal {
        let quantity = "Gain V(\(output))/V(\(input)) at \(SIFormat.string(frequency, unit: "Hz"))"
        let sweep = (frequency / 10)...(frequency * 10)
        return measuring(quantity, unit: "", requirement, analysis: .ac(sweep, pointsPerDecade: 10)) { _, result in
            let ac = try result.ac()
            let outputNode = try result.node(output), inputNode = try result.node(input)
            let index = ac.frequencies.indices.min { abs(log(ac.frequencies[$0] / frequency)) < abs(log(ac.frequencies[$1] / frequency)) }!
            let vin = ac.nodeVoltages[inputNode][index]
            guard vin.magnitude > 1e-12 else { throw Unmeasurable.absent("V(\(input)) has no AC signal.") }
            let ratio = ac.nodeVoltages[outputNode][index] / vin
            return ratio.re < 0 ? -ratio.magnitude : ratio.magnitude
        }
    }

    // MARK: Measuring

    /// A goal on a number measured from the result of `analysis`.
    private static func measuring(
        _ quantity: String, unit: String, _ requirement: Requirement, analysis: SimulationSettings,
        _ measure: @escaping @Sendable (Circuit, SimulationResult) throws -> Double
    ) -> Goal {
        Goal(title: "\(quantity) \(requirement.description(unit: unit))", analysis: analysis) { circuit, result in
            Self.status {
                let value = try measure(circuit, result!)
                let now = "Now: \(SIFormat.string(value, unit: unit, significantDigits: 4))"
                return requirement.isMet(by: value) ? .met(now) : .notMet(now)
            }
        }
    }

    private static func status(_ body: () throws -> GoalStatus) -> GoalStatus {
        do {
            return try body()
        } catch let failure as Unmeasurable {
            switch failure {
            case let .missing(reason): return .unavailable(reason)
            case let .absent(reason): return .notMet(reason)
            }
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    static func cutoffFrequency(_ magnitudes: [Double], _ frequencies: [Double], _ filter: Filter, net: String) throws -> Double {
        let indices = filter == .lowPass ? Array(frequencies.indices) : Array(frequencies.indices.reversed())
        let end = filter == .lowPass ? "low" : "high"
        let reference = magnitudes[indices[0]]
        guard reference > 1e-12 else {
            throw Unmeasurable.absent("V(\(net)) has no signal at \(SIFormat.string(frequencies[indices[0]], unit: "Hz")).")
        }
        let level = reference / 2.squareRoot()
        for (previous, index) in zip(indices, indices.dropFirst()) where magnitudes[index] < level {
            // Interpolate the crossing linearly in dB against log frequency.
            let (above, below) = (20 * log10(magnitudes[previous]), 20 * log10(max(magnitudes[index], 1e-300)))
            let fraction = (above - 20 * log10(level)) / (above - below)
            let (from, to) = (log10(frequencies[previous]), log10(frequencies[index]))
            return pow(10, from + fraction * (to - from))
        }
        throw Unmeasurable.absent("V(\(net)) never falls 3 dB below its \(end)-frequency level.")
    }

    static func peakFrequency(_ magnitudes: [Double], _ frequencies: [Double], net: String) throws -> Double {
        let dB = magnitudes.map { 20 * log10(max($0, 1e-300)) }
        let top = dB.indices.max { dB[$0] < dB[$1] }!
        guard top > 0, top < dB.count - 1, dB[top] > dB[0], dB[top] > dB[dB.count - 1] else {
            throw Unmeasurable.absent("V(\(net)) has no peak: it is largest at the edge of the sweep.")
        }
        // Fit a parabola through the top three points; the sweep is evenly spaced in log frequency.
        let curvature = dB[top - 1] - 2 * dB[top] + dB[top + 1]
        let offset = curvature == 0 ? 0 : 0.5 * (dB[top - 1] - dB[top + 1]) / curvature
        let step = log10(frequencies[top + 1] / frequencies[top])
        return pow(10, log10(frequencies[top]) + offset * step)
    }
}

/// Why a goal's quantity could not be measured.
enum Unmeasurable: Error {
    /// The circuit lacks the net or part the goal names, so the goal can't be checked yet.
    case missing(String)
    /// The quantity does not exist in this circuit, such as a filter with no −3 dB point: the goal is not met.
    case absent(String)
}

// MARK: - Helpers

extension SimulationSettings {
    fileprivate static var dc: SimulationSettings {
        var settings = SimulationSettings()
        settings.analysis = .operatingPoint
        return settings
    }

    fileprivate static func transient(stopTime: Double) -> SimulationSettings {
        var settings = SimulationSettings()
        settings.analysis = .transient
        settings.stopTime = stopTime
        return settings
    }

    fileprivate static func ac(_ sweep: ClosedRange<Double>, pointsPerDecade: Int) -> SimulationSettings {
        var settings = SimulationSettings()
        settings.analysis = .ac
        settings.startFrequency = sweep.lowerBound
        settings.stopFrequency = sweep.upperBound
        settings.pointsPerDecade = pointsPerDecade
        return settings
    }
}

extension SimulationResult {
    fileprivate func node(_ name: String) throws -> Int {
        guard let index = netlist.nodeNames.firstIndex(of: name) else {
            throw Unmeasurable.missing("No net is labeled “\(name)”. Press N and click a wire to add the label.")
        }
        return index
    }

    fileprivate func element(_ name: String, in circuit: Circuit) throws -> Int {
        if let index = netlist.elements.firstIndex(where: { $0.name == name }) { return index }
        if circuit.components.contains(where: { $0.name == name && $0.kind.hasValue }) {
            throw Unmeasurable.missing("\(name) is shorted: all of its pins are on the same net. A part placed on top of a wire is shorted by it.")
        }
        throw Unmeasurable.missing("There is no part named \(name).")
    }

    fileprivate func operatingPoint() throws -> OperatingPoint {
        guard case let .operatingPoint(op) = output else { throw Unmeasurable.missing("No DC operating point.") }
        return op
    }

    fileprivate func transient() throws -> TransientResult {
        guard case let .transient(transient) = output else { throw Unmeasurable.missing("No transient analysis.") }
        return transient
    }

    fileprivate func ac() throws -> ACResult {
        guard case let .ac(ac) = output else { throw Unmeasurable.missing("No AC sweep.") }
        return ac
    }
}

extension Array where Element == Double {
    /// The value at `t`, interpolated linearly between samples taken at the ascending `times`.
    fileprivate func interpolated(at t: Double, over times: [Double]) -> Double {
        guard let upper = times.firstIndex(where: { $0 >= t }) else { return last ?? 0 }
        guard upper > 0 else { return self[0] }
        let fraction = (t - times[upper - 1]) / (times[upper] - times[upper - 1])
        return self[upper - 1] + fraction * (self[upper] - self[upper - 1])
    }
}
