import Foundation
import Testing
@testable import CircuitCore

private func operatingPoint(_ circuit: Circuit) throws -> (SimulationResult, OperatingPoint) {
    var circuit = circuit
    circuit.simulation.analysis = .operatingPoint
    let result = try Simulator.run(circuit)
    guard case let .operatingPoint(op) = result.output else { throw SimulationError.cancelled }
    return (result, op)
}

private func transient(_ circuit: Circuit) throws -> (SimulationResult, TransientResult) {
    let result = try Simulator.run(circuit)
    guard case let .transient(transient) = result.output else { throw SimulationError.cancelled }
    return (result, transient)
}

private func voltage(_ net: String, _ result: SimulationResult, _ op: OperatingPoint) -> Double {
    op.nodeVoltages[result.netlist.nodeNames.firstIndex(of: net)!]
}

/// The samples of the net labeled `net`, as (time, voltage).
private func samples(_ net: String, _ result: SimulationResult, _ transient: TransientResult) -> [(Double, Double)] {
    Array(zip(transient.time, transient.nodeVoltages[result.netlist.nodeNames.firstIndex(of: net)!]))
}

private func setting(_ circuit: Circuit, _ name: String, _ change: (inout Component) -> Void) -> Circuit {
    var circuit = circuit
    change(&circuit.components[circuit.components.firstIndex { $0.name == name }!])
    return circuit
}

/// The number a goal measured, parsed back from its "Now: …" detail.
private func measure(_ goal: Goal, _ circuit: Circuit) -> Double? {
    var copy = circuit
    copy.simulation = goal.analysis!
    let detail = goal.check(circuit, try? Simulator.run(copy)).detail
    guard detail.hasPrefix("Now: ") else { return nil }
    return SIFormat.parse(String(detail.dropFirst(5)))
}

/// Comparator U1 with its + input on the source VP, its − input on VM, and its output on the net y.
private func comparatorCircuit(plus: Double, minus: Double) -> Circuit {
    var b = Bench()
    b.comparator("U1", plus: GridPoint(10, 10))
    b.vertical(.voltageSource, "VP", plus, top: GridPoint(4, 10))
    b.ground(at: GridPoint(4, 14))
    b.wire(GridPoint(4, 10), GridPoint(10, 10))
    b.label("m", at: GridPoint(10, 8))
    b.vertical(.voltageSource, "VM", minus, top: GridPoint(0, 4))
    b.label("m", at: GridPoint(0, 4))
    b.ground(at: GridPoint(0, 8))
    b.wire(GridPoint(14, 9), GridPoint(18, 9))
    b.label("y", at: GridPoint(18, 9))
    b.circuit.simulation.analysis = .operatingPoint
    return b.circuit
}

@Suite struct ChipTests {
    // MARK: Comparator

    @Test func comparatorTellsWhichInputIsHigher() throws {
        // 10 mV is ten times the width of the transition.
        for (plus, minus, high) in [(2.6, 2.5, true), (2.4, 2.5, false), (2.51, 2.5, true), (0.0, 0.01, false)] {
            let (result, op) = try operatingPoint(comparatorCircuit(plus: plus, minus: minus))
            #expect(abs(voltage("y", result, op) - (high ? 5 : 0)) < 0.01, "\(plus) vs \(minus)")
            #expect(result.netlist.warnings.isEmpty, "\(result.netlist.warnings)")
        }
        // At the threshold it amplifies, with a gain of V_DD/(4w) = 1250.
        let (result, op) = try operatingPoint(comparatorCircuit(plus: 2.5, minus: 2.5))
        #expect(abs(voltage("y", result, op) - 2.5) < 1e-9)
        let (_, slope) = ComparatorModel().target(0)
        #expect(abs(slope - 1250) < 1e-9)
    }

    @Test func comparatorOutputFollowsOnePropagationDelayLater() throws {
        var circuit = comparatorCircuit(plus: 3, minus: 2.5)
        var step = SourceWaveform(shape: .step)
        step.delay = 1e-6
        circuit = setting(circuit, "VP") { $0.waveform = step }
        circuit.simulation.analysis = .transient
        circuit.simulation.stopTime = 2e-6
        circuit.simulation.timeStep = 1e-9
        let (result, run) = try transient(circuit)
        let y = samples("y", result, run)
        func at(_ t: Double) -> Double { y.first { $0.0 >= t - 1e-12 }!.1 }
        // From rest the output waits 100 ns, then follows the input 100 ns late.
        #expect(at(50e-9) == 0)
        #expect(at(950e-9) == 0)
        #expect(at(1.095e-6) < 0.01)
        #expect(abs(at(1.11e-6) - 5) < 0.01)
    }

    @Test func schmittTriggerSwitchesAtTwoThresholds() throws {
        let (result, run) = try transient(Bench.schmittTrigger(feedback: 100e3))
        let input = samples("in", result, run), output = samples("out", result, run)
        // Where the output switches, after the first millisecond: up near 2.75 V and down near 2.25 V.
        for ((_, before), ((_, after), (_, v))) in zip(output, zip(output.dropFirst(), input.dropFirst()))
        where abs(after - before) > 2.5 && run.time[output.firstIndex { $0.1 == after }!] > 1e-3 {
            let threshold = after > before ? 2.75 : 2.25
            #expect(abs(v - threshold) < 0.05, "switching \(after > before ? "up" : "down") at \(v)")
        }
        // Without R2, noise makes the output chatter: twice as many rising edges as cycles.
        let chatter = try #require(measure(Tutorial.lesson(withID: "comparator")!.goals[0], Bench.schmittTrigger(feedback: nil)))
        #expect(chatter > 1.5e3)
    }

    @Test func transistorComparatorIsHighWhenThePlusInputIs() throws {
        let (result, run) = try transient(DiveInCircuits.comparatorTest)
        #expect(result.netlist.warnings.isEmpty)
        for ((_, input), (_, output)) in zip(samples("in", result, run), samples("out", result, run)) {
            if input > 2.6 { #expect(output > 4.9) }
            if input < 2.4 { #expect(output < 0.1) }
        }
    }

    // MARK: 555 timer

    @Test func astableOscillatesAtTheTextbookFrequency() throws {
        for (r1, r2, c) in [(1e3, 6.8e3, 100e-9), (4.7e3, 47e3, 10e-9), (10e3, 100e3, 1e-6)] {
            let expected = 1 / (log(2) * (r1 + 2 * r2) * c)
            let circuit = Bench.astable(r1: r1, r2: r2, c: c, stopTime: 6 / expected)
            let goal = Goal.frequency("out", after: 2 / expected, .near(expected, tolerance: 0.03), stopTime: 6 / expected,
                                      timeStep: 1e-3 / expected)
            #expect(goal.check(circuit, try Simulator.run(circuit.with(goal.analysis!))).isMet, "\(r1) \(r2) \(c)")
        }
        // V(cap) swings between ⅓ and ⅔ of the supply.
        let (result, run) = try transient(Bench.astable(r1: 1e3, r2: 6.8e3, c: 100e-9, stopTime: 6e-3))
        let cap = samples("cap", result, run).filter { $0.0 > 2e-3 }.map(\.1)
        #expect(abs(cap.min()! - 5.0 / 3) < 0.02)
        #expect(abs(cap.max()! - 10.0 / 3) < 0.02)
        #expect(result.netlist.warnings.isEmpty)
    }

    @Test func oneShotPulseLastsOnePointOneRC() throws {
        for (r, c) in [(91e3, 100e-9), (10e3, 1e-6)] {
            let expected = log(3) * r * c
            let width = try #require(measure(
                .pulseWidth("out", after: 0.5e-3, .near(expected, tolerance: 0.01), stopTime: 1e-3 + 1.5 * expected, timeStep: 2e-6),
                Bench.monostable(r: r, c: c, stopTime: 15e-3)))
            #expect(abs(width / expected - 1) < 2e-3, "\(r) \(c)")
        }
        // Before the trigger, the output is low and DIS holds the capacitor empty.
        let (result, run) = try transient(Bench.monostable(r: 91e3, c: 100e-9, stopTime: 15e-3))
        for ((t, out), (_, cap)) in zip(samples("out", result, run), samples("cap", result, run)) where t < 1e-3 {
            #expect(out < 1e-6 && cap < 1e-3)
        }
    }

    @Test func latchFollowsTheFunctionTable() {
        func latch(_ trigger: Double, _ threshold: Double, reset: Double = 5, previous: Bool) -> Bool {
            TimerModel.latch(trigger: trigger, threshold: threshold, control: 10.0 / 3, reset: reset, previous: previous)
        }
        #expect(latch(1, 2, previous: false))
        #expect(!latch(2, 4, previous: true))
        #expect(latch(2, 2, previous: true) && !latch(2, 2, previous: false))
        // The trigger wins over the threshold, and RESET wins over both.
        #expect(latch(1, 4, previous: false))
        #expect(!latch(1, 2, reset: 0.5, previous: true))
    }

    @Test func resetHoldsTheTimerOff() throws {
        var circuit = Bench.astable(r1: 1e3, r2: 6.8e3, c: 100e-9, stopTime: 3e-3)
        // Ground RESET instead of tying it to VCC: move its wire's top end to a ground symbol.
        circuit.wires.removeAll { $0.start == GridPoint(19, 6) }
        circuit.components.append(Component(kind: .ground, name: "GND", position: GridPoint(19, 6)))
        let (result, run) = try transient(circuit)
        #expect(samples("out", result, run).allSatisfy { $0.1 < 1e-6 })
        #expect(samples("cap", result, run).allSatisfy { $0.1 < 0.1 })
    }

    @Test func timerDCStartsReset() throws {
        // A one-shot at rest: the trigger is high, so the latch stays reset and DIS empties C1.
        let (result, op) = try operatingPoint(Bench.monostable(r: 91e3, c: 100e-9, stopTime: 15e-3))
        #expect(voltage("out", result, op) < 1e-3)
        #expect(voltage("cap", result, op) < 0.1)
        // The divider holds CTRL at ⅔ of the supply, and draws 5 V / 15 kΩ.
        let timer = result.netlist.elements.first { $0.kind == .timer }!
        #expect(abs(op.nodeVoltages[timer.nodes[4]] - 10.0 / 3) < 1e-6)
        let index = result.netlist.elements.firstIndex { $0.kind == .timer }!
        #expect(op.elementPowers[index] > 25.0 / 15e3 - 1e-9)
        // Pulling TRIG low sets it.
        let triggered = setting(Bench.monostable(r: 91e3, c: 100e-9, stopTime: 15e-3), "V2") { $0.waveform = SourceWaveform() }
        let (result2, op2) = try operatingPoint(triggered)
        #expect(abs(voltage("out", result2, op2) - 5) < 1e-3)
    }

    @Test func timerEquationsUseItsLatchState() throws {
        var circuit = Bench.astable(r1: 1e3, r2: 6.8e3, c: 100e-9, stopTime: 6e-3)
        let transientRows = try CircuitEquations(circuit: circuit, notation: .symbols).rows
        let output = try #require(transientRows.first { $0.label == "555 Timer U1 · output" })
        #expect(output.law.description == "I(U1) = (V(out) − q[U1]·V(N1))/R[out,U1]")
        #expect(output.solvedForm?.description == "G[out,U1]·V(out) − G[out,U1]·q[U1]·V(N1) − I(U1) = 0")
        let discharge = try #require(transientRows.first { $0.label == "555 Timer U1 · discharge" })
        #expect(discharge.law.description == "Idis(U1) = (1 − q[U1])·V(N3)/R[dis,U1]")
        // The divider appears in the node laws of VCC and CTRL.
        #expect(transientRows.contains { $0.law.description == "(V(N2) − V(N1))/5 kΩ + V(N2)/10 kΩ = 0" })

        circuit.simulation.analysis = .operatingPoint
        let values = try CircuitEquations(circuit: circuit, notation: .values)
        #expect(values.rows.first { $0.label == "555 Timer U1 · pull-up" }?.law.description == "Iup(U1) = q[U1]·(V(N1) − V(out))/10 Ω")
        #expect(values.notes.contains { $0.hasPrefix("At DC a 555's latch starts reset") })
    }

    // MARK: Voltage regulator

    @Test(arguments: [240.0, 390, 720])
    func regulatorFollowsTheLM317Formula(r2: Double) throws {
        var circuit = Bench.regulator(r2: r2)
        circuit.simulation.analysis = .operatingPoint
        let (result, op) = try operatingPoint(circuit)
        let expected = 1.25 * (1 + r2 / 240) + 50e-6 * r2
        // Within 0.1 %: the load's current through the 10 mΩ output resistance lowers it a little.
        #expect(abs(voltage("out", result, op) / expected - 1) < 1e-3)
        // The pass current feeds the load and the divider; the ADJ current returns through R2.
        let pass = op.elementCurrents[result.netlist.elements.firstIndex { $0.kind == .regulator }!]
        #expect(abs(pass - (expected / 100 + (expected - (expected - 1.25)) / 240)) < 1e-4)
    }

    @Test func regulatorDropsOutBelowItsHeadroom() throws {
        // Set to 7.56 V on 9 V ± 1 V: the output follows the input 2 V down in the troughs.
        let lesson = Tutorial.lesson(withID: "voltage-regulator")!
        let (result, run) = try transient(lesson.starter)
        for ((_, input), (t, output)) in zip(samples("in", result, run), samples("out", result, run)) where t > 1e-3 {
            #expect(abs(output - min(7.56, input - 2)) < 0.1)
        }
        // The pass transistor can't carry current backward: with the input gone, only the ADJ current
        // reaches the output, through R1.
        let off = setting(lesson.solution, "V1") { $0.value = 0; $0.waveform = SourceWaveform() }
        let (result2, op) = try operatingPoint(off)
        #expect(abs(voltage("out", result2, op)) < 0.01)
    }

    @Test func fixedRegulatorIsAGroundedAdjustableOne() throws {
        // A 7805: V_ref = 5 V, ADJ grounded.
        var b = Bench()
        b.vertical(.voltageSource, "V1", 12, top: GridPoint(4, 6))
        b.wire(GridPoint(4, 6), GridPoint(10, 6))
        b.regulator("U1", 5, at: GridPoint(13, 6))
        b.ground(at: GridPoint(13, 8))
        b.wire(GridPoint(16, 6), GridPoint(20, 6))
        b.label("out", at: GridPoint(20, 6))
        b.vertical(.resistor, "RL", 50, top: GridPoint(20, 6))
        b.ground(at: GridPoint(20, 10))
        b.ground(at: GridPoint(4, 10))
        let (result, op) = try operatingPoint(b.circuit)
        #expect(abs(voltage("out", result, op) - 5) < 2e-3)
        #expect(result.netlist.warnings.isEmpty)
    }

    @Test func regulatorOfPartsHoldsItsOutput() throws {
        let circuit = DiveInCircuits.regulatorTest
        let (result, run) = try transient(circuit)
        #expect(samples("out", result, run).allSatisfy { abs($0.1 - 1.25 * (1 + 394.0 / 240)) < 1e-3 })
        // Its ideal op-amp keeps it regulating with only a tenth of a volt to spare.
        let low = setting(circuit, "V1") { $0.value = 3.4; $0.waveform = SourceWaveform() }
        let (result2, op) = try operatingPoint(low)
        #expect(abs(voltage("out", result2, op) - 3.302) < 1e-3)
    }

    // MARK: Dive In

    @Test func timerOfPartsWorksLikeTheChip() throws {
        let circuit = DiveInCircuits.timerAstable
        let goal = Goal.frequency("out", after: 2e-3, .near(1 / (log(2) * 14.6e3 * 100e-9), tolerance: 0.03), stopTime: 6e-3)
        #expect(goal.check(circuit, try Simulator.run(circuit.with(goal.analysis!))).isMet)
        let (result, run) = try transient(circuit)
        let cap = samples("thr", result, run).filter { $0.0 > 2e-3 }.map(\.1)
        #expect(abs(cap.min()! - 5.0 / 3) < 0.02 && abs(cap.max()! - 10.0 / 3) < 0.02)
    }

    @Test func chipsHaveTopicsAndLessons() {
        for (kind, lesson) in [(ComponentKind.comparator, "comparator"), (.timer, "555-timer"), (.regulator, "voltage-regulator")] {
            #expect(DiveIn.topic(for: kind)?.lesson == lesson)
        }
        #expect(DiveIn.containers(of: "sr-latch").map(\.id).contains("timer"))
        #expect(DiveIn.containers(of: "comparator").map(\.id).contains("timer"))
    }

    // MARK: Documents

    @Test func chipsAreSavedWithTheCircuit() throws {
        for example in [Examples.timerAstable, Examples.comparatorHysteresis, Examples.adjustableRegulator] {
            #expect(try Circuit.decoded(from: example.circuit.encoded()) == example.circuit)
        }
        // Parameters saved without a key get their defaults.
        let parameters = try JSONDecoder().decode(ChipParameters.self, from: #"{"dropout": 1.1}"#.data(using: .utf8)!)
        #expect(parameters.dropout == 1.1)
        #expect(parameters.delay == ChipParameters.defaultComparatorDelay && parameters.adjustCurrent == ChipParameters.defaultAdjustCurrent)
    }

    @Test func chipsDescribeThemselves() {
        var regulator = Component(kind: .regulator, name: "U1", position: .zero)
        #expect(regulator.valueDescription == "Vref = 1.25 V")
        regulator.chip?.dropout = 1.2
        #expect(regulator.valueDescription == "Vref = 1.25 V, Vdo = 1.2 V")
        var comparator = Component(kind: .comparator, name: "U2", position: .zero)
        #expect(comparator.valueDescription.isEmpty)
        comparator.value = 3.3
        #expect(comparator.valueDescription == "3.3 V")
        #expect(Component(kind: .timer, name: "U3", position: .zero).chip == nil)
        #expect(ComponentKind.timer.pinName(1, of: 8) == "The trigger")
    }

    @Test func invalidChipParametersAreRejected() {
        var circuit = Bench.regulator(r2: 390)
        circuit = setting(circuit, "U1") { $0.chip?.dropout = -1 }
        #expect(throws: NetlistError.invalidValue(component: "U1", reason: "dropout voltage must be positive, or 0 for none.")) {
            try Netlist(circuit: circuit)
        }
        var comparator = comparatorCircuit(plus: 1, minus: 0)
        comparator = setting(comparator, "U1") { $0.value = 0 }
        #expect(throws: NetlistError.invalidValue(component: "U1", reason: "supply voltage must be greater than zero.")) {
            try Netlist(circuit: comparator)
        }
    }

    @Test func openPinsAreReportedExceptCTRL() throws {
        var circuit = Bench.astable(r1: 1e3, r2: 6.8e3, c: 100e-9, stopTime: 6e-3)
        #expect(try Netlist(circuit: circuit).warnings.isEmpty)
        circuit.wires.removeAll { $0.start == GridPoint(19, 6) }
        #expect(try Netlist(circuit: circuit).warnings == ["The reset pin of U1 is not connected to anything."])
    }
}

extension Circuit {
    /// A copy with other simulation settings.
    fileprivate func with(_ settings: SimulationSettings) -> Circuit {
        var circuit = self
        circuit.simulation = settings
        return circuit
    }
}
