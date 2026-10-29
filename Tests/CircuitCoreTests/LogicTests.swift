import Foundation
import Testing
@testable import CircuitCore

/// Logic gate U1 with its inputs on the nets a and b, driven by the DC sources VA and VB, and its
/// output on the net y, optionally loaded by a resistor to ground.
private func gateCircuit(
    _ function: LogicFunction, inputs: [Double], load: Double? = nil, delay: Double = LogicParameters.defaultDelay
) -> Circuit {
    var b = Bench()
    var parameters = LogicParameters(function: function)
    parameters.delay = delay
    b.circuit.components.append(Component(kind: .logicGate, name: "U1", position: GridPoint(10, 10), rotation: 0, logic: parameters))
    for (index, (net, volts)) in zip(["a", "b"], inputs).enumerated() {
        let x = 4 * index
        b.vertical(.voltageSource, "V\(net.uppercased())", volts, top: GridPoint(x, 0))
        b.ground(at: GridPoint(x, 4))
        b.label(net, at: GridPoint(x, 0))
    }
    let pins = b.circuit.components[0].pinPositions
    for (net, pin) in zip(["a", "b"], pins.dropLast()) { b.label(net, at: pin) }
    b.label("y", at: pins.last!)
    if let load {
        b.vertical(.resistor, "RL", load, top: pins.last!)
        b.ground(at: pins.last! + GridPoint(0, 4))
    }
    b.circuit.simulation.analysis = .operatingPoint
    return b.circuit
}

private func run(_ circuit: Circuit) throws -> (SimulationResult, OperatingPoint) {
    let result = try Simulator.run(circuit)
    guard case let .operatingPoint(op) = result.output else { throw SimulationError.cancelled }
    return (result, op)
}

private func voltage(_ net: String, _ result: SimulationResult, _ op: OperatingPoint) -> Double {
    op.nodeVoltages[result.netlist.nodeNames.firstIndex(of: net)!]
}

private let twoInputs = [(name: "A", source: "VA"), (name: "B", source: "VB")]

@Suite struct LogicTests {
    @Test(arguments: LogicFunction.allCases)
    func truthTable(function: LogicFunction) throws {
        for combination in 0..<(1 << function.inputCount) {
            let bits = (0..<function.inputCount).map { combination >> (function.inputCount - 1 - $0) & 1 == 1 }
            let (result, op) = try run(gateCircuit(function, inputs: bits.map { $0 ? 5 : 0 }))
            let expected = function.evaluate(bits) ? 5.0 : 0
            #expect(abs(voltage("y", result, op) - expected) < 1e-9, "\(function) \(bits)")
            #expect(result.netlist.warnings.isEmpty, "\(result.netlist.warnings)")
        }
        #expect(LogicFunction.xor.evaluate([true, false]) && !LogicFunction.xnor.evaluate([true, false]))
    }

    @Test(arguments: LogicFunction.allCases)
    func targetSlopesMatchTheTarget(function: LogicFunction) {
        let gate = LogicGateModel(function: function)
        for inputs in [[2.45, 2.6], [2.5, 2.5], [2.3, 4.9], [0.1, 2.52]] {
            let point = Array(inputs.prefix(function.inputCount))
            let (_, slopes) = gate.target(point)
            for j in point.indices {
                var above = point, below = point
                above[j] += 1e-6
                below[j] -= 1e-6
                let numeric = (gate.target(above).voltage - gate.target(below).voltage) / 2e-6
                #expect(abs(slopes[j] - numeric) <= 1e-5 * max(1, abs(numeric)), "\(function) \(point) input \(j)")
            }
        }
    }

    @Test func outputSagsThroughItsResistance() throws {
        let (result, op) = try run(gateCircuit(.not, inputs: [0], load: 1e3))
        let expected = 5 * 1e3 / (1e3 + LogicGateModel.outputResistance)
        #expect(abs(voltage("y", result, op) - expected) < 1e-9)
        // I(U1) flows into the output, so a gate sourcing current reads negative, like an op-amp.
        let gate = result.netlist.elements.firstIndex { $0.name == "U1" }!
        #expect(abs(op.elementCurrents[gate] + expected / 1e3) < 1e-8)
    }

    @Test func amplifiesAtTheThreshold() throws {
        // An inverter's gain at half the supply is V_DD·(¼)/w = 25.
        let (result, op) = try run(gateCircuit(.not, inputs: [2.5]))
        #expect(abs(voltage("y", result, op) - 2.5) < 1e-9)
        var circuit = gateCircuit(.not, inputs: [2.5])
        circuit.simulation.analysis = .ac
        circuit.simulation.startFrequency = 1e3
        circuit.simulation.stopFrequency = 1e7
        circuit.simulation.pointsPerDecade = 1
        let sweep = try Simulator.run(circuit)
        guard case let .ac(ac) = sweep.output else { throw SimulationError.cancelled }
        let y = ac.nodeVoltages[sweep.netlist.nodeNames.firstIndex(of: "y")!]
        #expect(abs(y[0].magnitude - 25) < 1e-3 && y[0].re < 0)
        // The 10 ns delay turns the phase by 360° · f · t_pd: 36° at 10 MHz.
        let phase = (y.last!.phase - Double.pi) * 180 / .pi
        #expect(abs(phase + 36) < 0.1)
        #expect(abs(y.last!.magnitude - 25) < 1e-3)
    }

    @Test func outputFollowsOnePropagationDelayLater() throws {
        var step = SourceWaveform(shape: .step)
        step.delay = 1e-6
        var circuit = gateCircuit(.not, inputs: [5], delay: 100e-9)
        circuit.components[circuit.components.firstIndex { $0.name == "VA" }!].waveform = step
        circuit.simulation.analysis = .transient
        circuit.simulation.stopTime = 2e-6
        circuit.simulation.timeStep = 1e-9
        let result = try Simulator.run(circuit)
        guard case let .transient(transient) = result.output else { throw SimulationError.cancelled }
        let y = transient.nodeVoltages[result.netlist.nodeNames.firstIndex(of: "y")!]
        func at(_ t: Double) -> Double { y[Int((t / 1e-9).rounded())] }
        // From rest, the output waits one delay before it rises, and falls one delay after the input rises.
        #expect(at(50e-9) == 0)
        #expect(abs(at(150e-9) - 5) < 1e-9)
        #expect(abs(at(1.095e-6) - 5) < 1e-9)
        #expect(abs(at(1.105e-6)) < 1e-9)
    }

    @Test func ringOscillatesAtTheTextbookFrequency() throws {
        let lesson = Tutorial.lesson(withID: "propagation-delay")!
        for (circuit, gates) in [(lesson.starter, 3.0), (lesson.solution, 5.0)] {
            let expected = 1 / (2 * gates * LogicParameters.defaultDelay)
            let goal = Goal.frequency("out", after: 150e-9, .near(expected, tolerance: 0.01), stopTime: 500e-9)
            var copy = circuit
            copy.simulation = goal.analysis!
            #expect(goal.check(circuit, try Simulator.run(copy)).isMet, "\(gates) gates")
        }
    }

    @Test func latchRemembers() throws {
        let result = try Simulator.run(Examples.srLatch.circuit)
        guard case let .transient(transient) = result.output else { throw SimulationError.cancelled }
        func level(_ net: String, at t: Double) -> Double {
            let index = transient.time.firstIndex { $0 >= t }!
            return transient.nodeVoltages[result.netlist.nodeNames.firstIndex(of: net)!][index]
        }
        // Reset at the start, set at 1 ms, reset again at 3 ms; held between the pulses.
        for (t, q) in [(0.8e-3, 0.0), (1.2e-3, 5), (2.5e-3, 5), (3.2e-3, 0), (4.5e-3, 0)] {
            #expect(abs(level("q", at: t) - q) < 1e-6, "q at \(t)")
            #expect(abs(level("qbar", at: t) - (5 - q)) < 1e-6, "qbar at \(t)")
        }
    }

    @Test func notGateHasOneInput() {
        var gate = Component(kind: .logicGate, name: "U1", position: GridPoint(10, 10), rotation: 0)
        #expect(gate.pinPositions == [GridPoint(8, 9), GridPoint(8, 11), GridPoint(12, 10)])
        gate.logic?.function = .not
        #expect(gate.pinPositions == [GridPoint(8, 10), GridPoint(12, 10)])
        #expect(gate.valueDescription == "NOT")
        gate.value = 3.3
        gate.logic?.delay = 20e-9
        #expect(gate.valueDescription == "NOT, 3.3 V, tpd = 20 ns")
        #expect(ComponentKind.logicGate.pinName(1, of: 3) == "Input B")
        #expect(ComponentKind.logicGate.pinName(1, of: 2) == "The output")
    }

    @Test func unconnectedInputsAreReported() throws {
        var circuit = gateCircuit(.nand, inputs: [5])
        circuit.components.removeAll { $0.kind == .netLabel && $0.name == "b" }
        let netlist = try Netlist(circuit: circuit)
        #expect(netlist.warnings == ["Input B of U1 is not connected to anything."])
        // An output that drives only a net label is there to be observed; one that drives nothing is not.
        circuit.components.removeAll { $0.kind == .netLabel && $0.name == "y" }
        #expect(try Netlist(circuit: circuit).warnings.contains("The output of U1 is not connected to anything."))
    }

    @Test func invalidParametersAreRejected() {
        var circuit = gateCircuit(.and, inputs: [5, 5])
        circuit.components[0].value = 0
        #expect(throws: NetlistError.invalidValue(component: "U1", reason: "supply voltage must be greater than zero.")) {
            try Netlist(circuit: circuit)
        }
        circuit.components[0].value = 5
        circuit.components[0].logic?.delay = -1e-9
        #expect(throws: NetlistError.invalidValue(component: "U1", reason: "propagation delay must be positive, or 0 for none.")) {
            try Netlist(circuit: circuit)
        }
    }

    @Test func gatesAreSavedWithTheCircuit() throws {
        let circuit = Examples.halfAdder.circuit
        let decoded = try Circuit.decoded(from: circuit.encoded())
        #expect(decoded == circuit)
        #expect(decoded.components.compactMap(\.logic).map(\.function) == [.xor, .and])
        // A gate saved without a delay gets the default one.
        let json = #"{"function": "nor"}"#.data(using: .utf8)!
        let parameters = try JSONDecoder().decode(LogicParameters.self, from: json)
        #expect(parameters.function == .nor && parameters.delay == LogicParameters.defaultDelay)
    }

    @Test func equationsDescribeTheGate() throws {
        let symbols = try CircuitEquations(circuit: gateCircuit(.nand, inputs: [5, 0]), notation: .symbols)
        let row = try #require(symbols.rows.first { $0.label == "NAND Gate U1" })
        #expect(row.law.description == "I(U1) = (V(y) − V[DD,U1]·NAND(V(a), V(b)))/R[out]")
        #expect(row.solvedForm?.description
            == "G[out]·V(y) + g[A,U1]·V(a) + g[B,U1]·V(b) − I(U1) = G[out]·V(y)[k] + g[A,U1]·V(a)[k] + g[B,U1]·V(b)[k] − I(U1)[k]")
        #expect(symbols.notes.contains { $0.hasPrefix("A logic gate drives its output") })
        #expect(symbols.notes.contains { $0.hasPrefix("Logic gates are not linear") })

        let values = try CircuitEquations(circuit: gateCircuit(.not, inputs: [5]), notation: .values)
        #expect(values.rows.first { $0.label == "NOT Gate U1" }?.law.description == "I(U1) = (V(y) − 5 V·NOT(V(a)))/50 Ω")

        var transient = gateCircuit(.nor, inputs: [5, 0])
        transient.simulation.analysis = .transient
        let delayed = try CircuitEquations(circuit: transient, notation: .symbols)
        let law = try #require(delayed.rows.first { $0.label == "NOR Gate U1" }?.law)
        #expect(law.description == "I(U1) = (V(y) − V[DD,U1]·NOR(V(a)(t − t[pd,U1]), V(b)(t − t[pd,U1])))/R[out]")
        // Delayed inputs are known values, not unknowns.
        #expect(law.runs.filter { $0.style == .unknown }.map(\.text) == ["I(U1)", "V(y)"])
    }

    @Test func truthTableGoalExplainsMistakes() {
        let goal = Goal.truthTable("y", inputs: twoInputs, "y = A XOR B") { $0[0] != $0[1] }
        #expect(goal.check(gateCircuit(.xor, inputs: [0, 0]), nil) == .met("Now: 0 1 1 0 for A B = 00 to 11"))
        #expect(goal.check(gateCircuit(.or, inputs: [0, 0]), nil) == .notMet("With A = 1, B = 1: V(y) = 5 V, which is 1."))
        var half = gateCircuit(.not, inputs: [2.5])
        half.components.removeAll { $0.name == "VB" }
        #expect(goal.check(half, nil) == .unavailable("There is no voltage source named VB for input B."))
        // The sources' waveforms don't matter: each combination is a DC analysis.
        let lesson = Tutorial.lesson(withID: "logic-gates")!
        #expect(lesson.starter.simulation.analysis == .transient)
    }

    @Test func gateGoalsCheckTheParts() {
        let onlyNAND = Goal.onlyGates(.nand)
        #expect(onlyNAND.check(Tutorial.lesson(withID: "nand-universal")!.solution, nil).isMet)
        #expect(onlyNAND.check(gateCircuit(.and, inputs: [0, 0]), nil) == .notMet("U1 is AND."))
        #expect(onlyNAND.check(Circuit(), nil) == .notMet("There are none yet."))
        let avoids = Goal.avoids(.logicGate, "Use MOSFETs, not logic gates")
        #expect(avoids.check(DiveInCircuits.cmosGate(.nand), nil).isMet)
        #expect(avoids.check(gateCircuit(.and, inputs: [0, 0]), nil) == .notMet("U1 is a logic gate."))
    }

    /// The transistor-level gates of Dive In compute what their pages say.
    @Test func transistorGatesComputeTheirFunctions() {
        let cases: [(Circuit, String, String, @Sendable ([Bool]) -> Bool)] = [
            (DiveInCircuits.cmosGate(.nand), "y", "NAND", { !($0[0] && $0[1]) }),
            (DiveInCircuits.cmosGate(.nor), "y", "NOR", { !($0[0] || $0[1]) }),
            (DiveInCircuits.cmosAND, "n", "NAND inside AND", { !($0[0] && $0[1]) }),
            (DiveInCircuits.cmosAND, "y", "AND", { $0[0] && $0[1] }),
            (DiveInCircuits.xorFromNAND, "y", "XOR", { $0[0] != $0[1] }),
            (Examples.halfAdder.circuit, "s", "sum", { $0[0] != $0[1] }),
            (Examples.halfAdder.circuit, "c", "carry", { $0[0] && $0[1] }),
        ]
        for (circuit, output, name, expected) in cases {
            let status = Goal.truthTable(output, inputs: twoInputs, name, expected).check(circuit, nil)
            #expect(status.isMet, "\(name): \(status)")
        }
    }

    @Test func diveInFollowsTheGateFunction() {
        for function in LogicFunction.allCases {
            let gate = Component(kind: .logicGate, name: "U1", position: .zero, logic: LogicParameters(function: function))
            let topic = DiveIn.topic(for: gate)
            #expect(topic?.id == DiveIn.topicID(for: function))
            #expect(topic?.category == .logic)
        }
        #expect(DiveIn.topic(for: Component(kind: .resistor, name: "R1", position: .zero))?.id == "resistor")
        #expect(DiveIn.topic(for: .logicGate)?.id == "logic-gate")
    }

    @Test func mosfetStepsAreLimitedLikeSPICE() {
        // A gate far below threshold may only come up to just past it in one step.
        #expect(MOSFETModel.limitGate(1e10, from: 0, threshold: 1) == 1.5)
        #expect(MOSFETModel.limitGate(0.8, from: 0, threshold: 1) == 0.8)
        #expect(MOSFETModel.limitDrain(1e10, from: 0) == 4)
        #expect(MOSFETModel.limitDrain(1e10, from: 5) == 17)
        let model = MOSFETModel(threshold: 1, transconductance: 2e-3)
        #expect(model.limitStep([2.25, 3.75], from: [2, 3.5]) == [2.25, 3.75])
        // P-channel voltages are limited in the mirrored, n-channel sense.
        let p = MOSFETModel(polarity: .p, threshold: 1, transconductance: 2e-3)
        #expect(p.limitStep([-1e10, -5], from: [0, -5]) == [-1.5, -2])
    }
}
