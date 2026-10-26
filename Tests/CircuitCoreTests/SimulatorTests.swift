import Foundation
import Testing
@testable import CircuitCore

/// Small helpers for building schematics in code. Two-terminal parts span 4 grid units.
private struct Builder {
    var circuit = Circuit()

    /// Places a horizontal two-terminal part with pin 1 at `from` (pin 2 at from + (4, 0)).
    @discardableResult
    mutating func horizontal(_ kind: ComponentKind, _ value: Double, at from: GridPoint, name: String? = nil) -> Component {
        let c = Component(kind: kind, name: name ?? circuit.nextName(for: kind), position: from + GridPoint(2, 0), rotation: 0, value: value)
        circuit.components.append(c)
        return c
    }

    /// Places a vertical two-terminal part with pin 1 at `top` (pin 2 at top + (0, 4)).
    @discardableResult
    mutating func vertical(_ kind: ComponentKind, _ value: Double, top: GridPoint, name: String? = nil, waveform: SourceWaveform = SourceWaveform()) -> Component {
        let c = Component(kind: kind, name: name ?? circuit.nextName(for: kind), position: top + GridPoint(0, 2), rotation: 1, value: value, waveform: waveform)
        circuit.components.append(c)
        return c
    }

    /// Places an op-amp pointing right with its origin at `origin`: + input at origin + (−2, 1),
    /// − input at origin + (−2, −1), output at origin + (2, 0).
    @discardableResult
    mutating func opAmp(at origin: GridPoint, gain: Double = 1e5, name: String? = nil) -> Component {
        let c = Component(kind: .opAmp, name: name ?? circuit.nextName(for: .opAmp), position: origin, rotation: 0, value: gain)
        circuit.components.append(c)
        return c
    }

    mutating func ground(at p: GridPoint) {
        circuit.components.append(Component(kind: .ground, name: "GND", position: p))
    }

    mutating func label(_ name: String, at p: GridPoint) {
        circuit.components.append(Component(kind: .netLabel, name: name, position: p))
    }

    mutating func wire(_ a: GridPoint, _ b: GridPoint) {
        circuit.wires.append(Wire(start: a, end: b))
    }
}

/// Source on the left (x = 0) from y = 0 to 4, ground at the bottom, series element(s) along the top.
private func seriesCircuit(
    source: SourceWaveform = SourceWaveform(), sourceValue: Double = 1,
    series: [(ComponentKind, Double)], shunt: (ComponentKind, Double)
) -> Builder {
    var b = Builder()
    b.vertical(.voltageSource, sourceValue, top: GridPoint(0, 0), waveform: source)
    var x = 0
    for (index, part) in series.enumerated() {
        b.horizontal(part.0, part.1, at: GridPoint(x, 0))
        if index == series.count - 1 { b.label("out", at: GridPoint(x + 4, 0)) }
        x += 4
    }
    b.vertical(shunt.0, shunt.1, top: GridPoint(x, 0))
    b.wire(GridPoint(0, 4), GridPoint(x, 4))
    b.ground(at: GridPoint(0, 4))
    return b
}

private func node(_ result: SimulationResult, _ name: String) -> Int {
    result.netlist.nodeNames.firstIndex(of: name)!
}

private func element(_ result: SimulationResult, _ name: String) -> Int {
    result.netlist.elements.firstIndex { $0.name == name }!
}

@Suite struct OperatingPointTests {
    @Test func voltageDivider() throws {
        var b = seriesCircuit(sourceValue: 10, series: [(.resistor, 1000)], shunt: (.resistor, 3000))
        b.circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(b.circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        #expect(abs(op.nodeVoltages[node(result, "out")] - 7.5) < 1e-6)
        #expect(abs(op.elementCurrents[element(result, "R1")] - 2.5e-3) < 1e-9)
        // Source current flows + → − inside the source, so a source delivering power reads negative.
        #expect(abs(op.elementCurrents[element(result, "V1")] + 2.5e-3) < 1e-9)
    }

    @Test func capacitorIsOpenAndInductorIsShortAtDC() throws {
        var b = seriesCircuit(sourceValue: 5, series: [(.inductor, 1e-3), (.resistor, 100)], shunt: (.capacitor, 1e-6))
        b.circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(b.circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        #expect(abs(op.nodeVoltages[node(result, "out")] - 5) < 1e-6)
        #expect(abs(op.elementCurrents[element(result, "L1")]) < 1e-9)
    }

    @Test func gminLeakageIsReportedAsZero() throws {
        // At DC the capacitor is open, so no current flows and R1 drops nothing.
        var b = seriesCircuit(sourceValue: 5, series: [(.resistor, 2200)], shunt: (.capacitor, 1e-6))
        b.circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(b.circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        #expect(op.elementCurrents[element(result, "R1")] == 0)
        #expect(op.elementVoltages[element(result, "R1")] == 0)
        #expect(op.elementCurrents[element(result, "V1")] == 0)
        #expect(abs(op.elementVoltages[element(result, "C1")] - 5) < 1e-6)
    }

    @Test func currentSourceIntoResistor() throws {
        var b = Builder()
        // Current flows pin 1 → pin 2 inside the source; pin 1 at the bottom (ground) pushes current up into "top".
        b.circuit.components.append(Component(kind: .currentSource, name: "I1", position: GridPoint(0, 2), rotation: 3, value: 2e-3))
        b.vertical(.resistor, 1000, top: GridPoint(4, 0))
        b.wire(GridPoint(0, 0), GridPoint(4, 0))
        b.wire(GridPoint(0, 4), GridPoint(4, 4))
        b.label("top", at: GridPoint(0, 0))
        b.ground(at: GridPoint(0, 4))
        b.circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(b.circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        #expect(abs(op.nodeVoltages[node(result, "top")] - 2) < 1e-6)
    }

    @Test func voltageSourceLoopIsReportedAsSingular() throws {
        var b = Builder()
        b.vertical(.voltageSource, 1, top: GridPoint(0, 0))
        b.vertical(.voltageSource, 2, top: GridPoint(4, 0))
        b.wire(GridPoint(0, 0), GridPoint(4, 0))
        b.wire(GridPoint(0, 4), GridPoint(4, 4))
        b.ground(at: GridPoint(0, 4))
        b.circuit.simulation.analysis = .operatingPoint
        #expect {
            try Simulator.run(b.circuit)
        } throws: { error in
            if case .singular = error as? SimulationError { return true }
            return false
        }
    }
}

@Suite struct TransientTests {
    @Test(arguments: [SimulationSettings.IntegrationMethod.trapezoidal, .backwardEuler])
    func rcChargingCurve(method: SimulationSettings.IntegrationMethod) throws {
        // τ = RC = 1 ms
        var b = seriesCircuit(sourceValue: 1, series: [(.resistor, 1000)], shunt: (.capacitor, 1e-6))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 5e-3
        b.circuit.simulation.timeStep = 1e-6
        b.circuit.simulation.integrationMethod = method
        let result = try Simulator.run(b.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let out = tr.nodeVoltages[node(result, "out")]
        #expect(out.first == 0)
        let tolerance = method == .trapezoidal ? 1e-5 : 1e-3
        for (t, v) in zip(tr.time, out) where t > 0 {
            #expect(abs(v - (1 - exp(-t / 1e-3))) < tolerance)
        }
    }

    @Test func rcStartsAtOperatingPointWhenRequested() throws {
        var b = seriesCircuit(sourceValue: 3, series: [(.resistor, 1000)], shunt: (.capacitor, 1e-6))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.initialConditions = .operatingPoint
        b.circuit.simulation.stopTime = 1e-3
        let result = try Simulator.run(b.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        for v in tr.nodeVoltages[node(result, "out")] { #expect(abs(v - 3) < 1e-6) }
    }

    @Test func seriesRLCStepResponseMatchesAnalytic() throws {
        // R = 10 Ω, L = 1 mH, C = 1 µF: ω0 = 31623 rad/s, α = R/2L = 5000 /s (underdamped).
        let r = 10.0, l = 1e-3, c = 1e-6
        var b = seriesCircuit(sourceValue: 1, series: [(.resistor, r), (.inductor, l)], shunt: (.capacitor, c))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 2e-3
        b.circuit.simulation.timeStep = 0.2e-6
        let result = try Simulator.run(b.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }

        let alpha = r / (2 * l)
        let w0 = 1 / sqrt(l * c)
        let wd = sqrt(w0 * w0 - alpha * alpha)
        func analytic(_ t: Double) -> Double {
            1 - exp(-alpha * t) * (cos(wd * t) + alpha / wd * sin(wd * t))
        }
        let out = tr.nodeVoltages[node(result, "out")]
        var maxError = 0.0
        for (t, v) in zip(tr.time, out) { maxError = max(maxError, abs(v - analytic(t))) }
        #expect(maxError < 1e-3)
        // Overshoot exists for an underdamped circuit.
        #expect(out.max()! > 1.5)
    }

    @Test func lcTankConservesEnergyWithTrapezoidal() throws {
        // Capacitor charged to 1 V via operating point, then a step source drops to 0.
        var source = SourceWaveform(shape: .step)
        source.initialValue = 1
        var b = seriesCircuit(source: source, sourceValue: 0, series: [(.inductor, 1e-3)], shunt: (.capacitor, 1e-6))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.initialConditions = .operatingPoint
        b.circuit.simulation.stopTime = 5e-3
        b.circuit.simulation.timeStep = 0.5e-6
        let result = try Simulator.run(b.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let out = tr.nodeVoltages[node(result, "out")]
        // Undamped: amplitude stays at 1 V (trapezoidal integration is energy-preserving).
        let late = out.suffix(out.count / 3)
        #expect(abs(late.max()! - 1) < 1e-3)
        #expect(abs(late.min()! + 1) < 1e-3)
    }

    @Test func sinePulseAndStepWaveforms() {
        var sine = SourceWaveform(shape: .sine)
        sine.amplitude = 2
        sine.frequency = 50
        #expect(abs(sine.value(at: 0.005, level: 1) - 3) < 1e-12)

        var pulse = SourceWaveform(shape: .pulse)
        pulse.initialValue = 0
        pulse.delay = 1
        pulse.riseTime = 1
        pulse.pulseWidth = 2
        pulse.fallTime = 1
        pulse.period = 10
        #expect(pulse.value(at: 0.5, level: 5) == 0)
        #expect(pulse.value(at: 1.5, level: 5) == 2.5)
        #expect(pulse.value(at: 3, level: 5) == 5)
        #expect(pulse.value(at: 4.5, level: 5) == 2.5)
        #expect(pulse.value(at: 8, level: 5) == 0)
        #expect(pulse.value(at: 13, level: 5) == 5)

        var step = SourceWaveform(shape: .step)
        step.initialValue = -1
        #expect(step.value(at: 0, level: 1) == -1)
        #expect(step.value(at: 1e-9, level: 1) == 1)
    }

    @Test func rejectsHugeStepCounts() {
        var b = seriesCircuit(series: [(.resistor, 1)], shunt: (.capacitor, 1))
        b.circuit.simulation.stopTime = 1
        b.circuit.simulation.timeStep = 1e-9
        #expect(throws: SimulationError.self) { try Simulator.run(b.circuit) }
    }
}

@Suite struct ACTests {
    @Test func rcLowPassCornerFrequency() throws {
        let r = 1000.0, c = 1e-6
        var b = seriesCircuit(series: [(.resistor, r)], shunt: (.capacitor, c))
        b.circuit.simulation.analysis = .ac
        let fc = 1 / (2 * Double.pi * r * c)
        b.circuit.simulation.startFrequency = fc / 100
        b.circuit.simulation.stopFrequency = fc * 100
        b.circuit.simulation.pointsPerDecade = 10  // odd number of points → fc is the middle sample
        let result = try Simulator.run(b.circuit)
        guard case let .ac(ac) = result.output else { Issue.record("wrong output"); return }
        let mid = ac.frequencies.count / 2
        #expect(abs(ac.frequencies[mid] - fc) / fc < 1e-9)
        let h = ac.nodeVoltages[node(result, "out")][mid]
        #expect(abs(20 * log10(h.magnitude) + 3.0103) < 1e-3)
        #expect(abs(h.phase * 180 / .pi + 45) < 1e-3)
        // Far above the corner: −20 dB/decade.
        let last = ac.nodeVoltages[node(result, "out")].last!
        #expect(abs(20 * log10(last.magnitude) + 40) < 0.01)
    }

    @Test func seriesRLCResonance() throws {
        // Band-pass: output across R peaks at f0 = 1/(2π√LC) with unity gain.
        let l = 1e-3, c = 1e-6
        var b = seriesCircuit(series: [(.inductor, l), (.capacitor, c)], shunt: (.resistor, 50))
        b.circuit.simulation.analysis = .ac
        b.circuit.simulation.startFrequency = 100
        b.circuit.simulation.stopFrequency = 100e3
        b.circuit.simulation.pointsPerDecade = 200
        let result = try Simulator.run(b.circuit)
        guard case let .ac(ac) = result.output else { Issue.record("wrong output"); return }
        let gains = ac.nodeVoltages[node(result, "out")].map(\.magnitude)
        let peak = gains.indices.max { gains[$0] < gains[$1] }!
        let f0 = 1 / (2 * Double.pi * sqrt(l * c))
        #expect(abs(ac.frequencies[peak] - f0) / f0 < 0.01)
        #expect(abs(gains[peak] - 1) < 1e-3)
    }
}

/// A multi-pin part wired with net labels: its pins are on the named nets (in pin order), and
/// the other parts sit elsewhere and connect through labels of the same names. Net "0" is ground.
private struct DeviceBench {
    var b = Builder()
    private var column = 0

    init(_ kind: ComponentKind, pins nets: [String], value: Double? = nil, transistor: TransistorParameters? = nil) {
        let device = Component(
            kind: kind, name: b.circuit.nextName(for: kind), position: GridPoint(2, -10), rotation: 0,
            value: value, transistor: transistor)
        b.circuit.components.append(device)
        for (net, pin) in zip(nets, device.pinPositions) { attach(net, at: pin) }
    }

    /// An op-amp with its + input, − input, and output on the named nets.
    init(plus: String, minus: String, out: String = "out", gain: Double = 1e5) {
        self.init(.opAmp, pins: [plus, minus, out], value: gain)
    }

    /// A vertical part from net `top` down to net `bottom`, in its own column. A current source
    /// pushes its current out of its bottom pin, into `bottom`.
    mutating func part(_ kind: ComponentKind, _ value: Double, from top: String, to bottom: String) {
        let x = column
        column += 4
        b.vertical(kind, value, top: GridPoint(x, 0))
        attach(top, at: GridPoint(x, 0))
        attach(bottom, at: GridPoint(x, 4))
    }

    private mutating func attach(_ net: String, at point: GridPoint) {
        if net == "0" { b.ground(at: point) } else { b.label(net, at: point) }
    }

    func operatingPoint() throws -> (SimulationResult, OperatingPoint) {
        var circuit = b.circuit
        circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(circuit)
        guard case let .operatingPoint(op) = result.output else { throw SimulationError.invalidSettings("wrong output") }
        return (result, op)
    }
}

@Suite struct OpAmpTests {
    /// Closed-loop gain of a non-inverting amplifier with open-loop gain `a`: G/(1 + G/a), G = 1 + R2/R1.
    private func nonInvertingGain(r1: Double, r2: Double, a: Double) -> Double {
        let ideal = 1 + r2 / r1
        return ideal / (1 + ideal / a)
    }

    @Test func nonInvertingAmplifier() throws {
        var bench = DeviceBench(plus: "in", minus: "fb")
        bench.part(.voltageSource, 0.5, from: "in", to: "0")
        bench.part(.resistor, 1e3, from: "fb", to: "0")
        bench.part(.resistor, 3e3, from: "fb", to: "out")
        let (result, op) = try bench.operatingPoint()
        #expect(result.netlist.warnings.isEmpty, "\(result.netlist.warnings)")
        let out = op.nodeVoltages[node(result, "out")]
        // Tolerances here allow for the gmin leakage at each node.
        #expect(abs(out - 0.5 * nonInvertingGain(r1: 1e3, r2: 3e3, a: 1e5)) < 1e-8)
        #expect(abs(out - 2) < 1e-3)
        // The inputs draw no current, so the source supplies nothing.
        #expect(op.elementCurrents[element(result, "V1")] == 0)
    }

    @Test func invertingAmplifier() throws {
        var bench = DeviceBench(plus: "0", minus: "fb")
        bench.part(.voltageSource, 1, from: "in", to: "0")
        bench.part(.resistor, 1e3, from: "in", to: "fb")
        bench.part(.resistor, 10e3, from: "fb", to: "out")
        let (result, op) = try bench.operatingPoint()
        let out = op.nodeVoltages[node(result, "out")], fb = op.nodeVoltages[node(result, "fb")]
        #expect(abs(out + 10 / (1 + 11 / 1e5)) < 1e-8)
        #expect(abs(fb) < 1e-3, "virtual ground")
        // The output sinks the 1 mA that flows from the input through R1 and R2.
        let u1 = element(result, "U1")
        #expect(abs(op.elementCurrents[u1] - (fb - out) / 10e3) < 1e-10)
        #expect(abs(op.elementCurrents[u1] - 1e-3) < 1e-6)
        // An op-amp reports its output voltage, so voltage × current is the power its output absorbs.
        #expect(op.elementVoltages[u1] == out)
    }

    @Test func followerSourcesLoadCurrent() throws {
        var bench = DeviceBench(plus: "in", minus: "out")
        bench.part(.voltageSource, 2, from: "in", to: "0")
        bench.part(.resistor, 1e3, from: "out", to: "0")
        let (result, op) = try bench.operatingPoint()
        #expect(abs(op.nodeVoltages[node(result, "out")] - 2 / (1 + 1 / 1e5)) < 1e-8)
        // Current flows out of the output pin, so the current into it is negative, as for a source delivering power.
        #expect(abs(op.elementCurrents[element(result, "U1")] + 2e-3) < 1e-7)
    }

    @Test func openLoopOutputIsLinear() throws {
        var bench = DeviceBench(plus: "in", minus: "0", gain: 2e5)
        bench.part(.voltageSource, 1e-3, from: "in", to: "0")
        let (result, op) = try bench.operatingPoint()
        // No supply rails: 1 mV × 200k is 200 V.
        #expect(abs(op.nodeVoltages[node(result, "out")] - 200) < 1e-6)
    }

    @Test func gainMustBePositive() {
        var bench = DeviceBench(plus: "in", minus: "out", gain: 0)
        bench.part(.voltageSource, 1, from: "in", to: "0")
        #expect(throws: NetlistError.invalidValue(component: "U1", reason: "open-loop gain must be greater than zero.")) {
            try Netlist(circuit: bench.b.circuit)
        }
    }

    @Test func sallenKeyMatchesTransferFunction() throws {
        let r1 = 10e3, r2 = 10e3, c1 = 22e-9, c2 = 10e-9
        let result = try Simulator.run(Examples.sallenKeyLowPass.circuit)
        guard case let .ac(ac) = result.output else { Issue.record("wrong output"); return }
        let input = ac.nodeVoltages[node(result, "in")], output = ac.nodeVoltages[node(result, "out")]
        for (index, f) in ac.frequencies.enumerated() {
            // H(jω) = 1 / (1 − ω²·R1·R2·C1·C2 + jω·C2·(R1 + R2)) for an ideal op-amp.
            let w = 2 * Double.pi * f
            let expected = Complex.one / Complex(1 - w * w * r1 * r2 * c1 * c2, w * c2 * (r1 + r2))
            let h = output[index] / input[index]
            #expect((h - expected).magnitude < 1e-4 * max(expected.magnitude, 1e-3), "f = \(f)")
        }
        // Unity gain in the pass band.
        #expect(abs((output[0] / input[0]).magnitude - 1) < 1e-3)
    }

    @Test func invertingAmplifierTransient() throws {
        let result = try Simulator.run(Examples.invertingAmplifier.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let input = tr.nodeVoltages[node(result, "in")], output = tr.nodeVoltages[node(result, "out")]
        #expect(abs(input.max()! - 0.5) < 1e-3)
        for (vin, vout) in zip(input, output) {
            #expect(abs(vout + 10 * vin / (1 + 11 / 1e5)) < 1e-8)
        }
    }
}

@Suite struct DiodeTests {
    /// Root of an increasing function on [low, high] by bisection.
    private func solve(_ low: Double, _ high: Double, _ f: (Double) -> Double) -> Double {
        var low = low, high = high
        for _ in 0..<200 {
            let mid = (low + high) / 2
            if f(mid) > 0 { high = mid } else { low = mid }
        }
        return (low + high) / 2
    }

    private func shockley(_ v: Double, is: Double = 1e-14, n: Double = 1) -> Double {
        `is` * (exp(v / (n * DiodeModel.thermalVoltage)) - 1)
    }

    /// Voltage across a diode fed from `source` through `r`: (source − v)/r = I(v).
    private func diodeVoltage(source: Double, r: Double, n: Double = 1) -> Double {
        solve(-abs(source) - 1, abs(source) + 1) { v in shockley(v, n: n) - (source - v) / r }
    }

    /// V1 through R1 into a diode D1 from "out" down to ground.
    private func biasCircuit(source: Double, r: Double, n: Double? = nil) -> Circuit {
        var b = seriesCircuit(sourceValue: source, series: [(.resistor, r)], shunt: (.diode, 1e-14))
        let d1 = b.circuit.components.firstIndex { $0.name == "D1" }!
        b.circuit.components[d1].emissionCoefficient = n
        return b.circuit
    }

    @Test(arguments: [(5.0, 1e3, 1.0), (5.0, 1e3, 2.0), (1.0, 100e3, 1.0), (100.0, 1.0, 1.0)])
    func forwardBias(source: Double, r: Double, n: Double) throws {
        var circuit = biasCircuit(source: source, r: r, n: n)
        circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        let expected = diodeVoltage(source: source, r: r, n: n)
        let v = op.nodeVoltages[node(result, "out")]
        #expect(abs(v - expected) < 1e-6, "V(out) = \(v), expected \(expected)")
        // The diode's current is the resistor's.
        let current = op.elementCurrents[element(result, "D1")]
        #expect(abs(current - op.elementCurrents[element(result, "R1")]) <= 1e-6 * abs(current))
        #expect(abs(current - shockley(v, n: n)) <= 2e-3 * abs(current))
    }

    @Test func reverseBiasBlocks() throws {
        var circuit = biasCircuit(source: -5, r: 1e3)
        circuit.simulation.analysis = .operatingPoint
        let result = try Simulator.run(circuit)
        guard case let .operatingPoint(op) = result.output else { Issue.record("wrong output"); return }
        #expect(abs(op.nodeVoltages[node(result, "out")] + 5) < 1e-6)
        #expect(abs(op.elementCurrents[element(result, "D1")]) < 1e-12)
    }

    @Test func smallSignalConductanceAtOperatingPoint() throws {
        var circuit = biasCircuit(source: 5, r: 1e3)
        circuit.simulation.analysis = .ac
        circuit.simulation.startFrequency = 10
        circuit.simulation.stopFrequency = 1e3
        let result = try Simulator.run(circuit)
        guard case let .ac(ac) = result.output else { Issue.record("wrong output"); return }
        // A divider of R1 and the diode's dynamic resistance 1/G, with G = (I + Is)/Vt.
        let v = diodeVoltage(source: 5, r: 1e3)
        let g = (shockley(v) + 1e-14) / DiodeModel.thermalVoltage
        let expected = 1 / (1 + 1e3 * g)
        for value in ac.nodeVoltages[node(result, "out")] {
            #expect(abs(value.magnitude - expected) < 1e-3 * expected)
            #expect(abs(value.phase) < 1e-9)
        }
    }

    @Test(arguments: [SimulationSettings.IntegrationMethod.trapezoidal, .backwardEuler])
    func clipperFollowsDiodeCurves(method: SimulationSettings.IntegrationMethod) throws {
        // No capacitance: each sample must solve (in − out)/R1 = I_D1(out) − I_D2(−out).
        var circuit = Examples.diodeClipper.circuit
        circuit.simulation.integrationMethod = method
        let result = try Simulator.run(circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let input = tr.nodeVoltages[node(result, "in")], output = tr.nodeVoltages[node(result, "out")]
        for (vin, vout) in zip(input, output) {
            let expected = solve(-4, 4) { v in shockley(v) - shockley(-v) - (vin - v) / 1e3 }
            #expect(abs(vout - expected) < 1e-5, "in = \(vin)")
        }
        #expect(output.max()! > 0.6 && output.max()! < 0.75)
        #expect(output.min()! < -0.6 && output.min()! > -0.75)
    }

    @Test(arguments: [SimulationSettings.IntegrationMethod.trapezoidal, .backwardEuler])
    func rectifierChargesAndHolds(method: SimulationSettings.IntegrationMethod) throws {
        var circuit = Examples.halfWaveRectifier.circuit
        circuit.simulation.integrationMethod = method
        let result = try Simulator.run(circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let out = tr.nodeVoltages[node(result, "out")], diode = tr.elementCurrents[element(result, "D1")]
        // The diode only conducts forward; reverse current is at most leakage.
        #expect(diode.min()! > -1e-9)
        // The capacitor charges to the 5 V peak less a diode drop, then sags between peaks.
        let settled = zip(tr.time, out).filter { $0.0 > 30e-3 }.map(\.1)
        #expect(settled.max()! > 4.1 && settled.max()! < 4.5)
        #expect(settled.max()! - settled.min()! < 1.0)
        #expect(settled.min()! > 3.3)
    }
}

/// Independent Ebers–Moll laws (NPN, β_R = 1) to check the simulator against.
private func ebersMoll(vbe: Double, vbc: Double, beta: Double = 100, is: Double = 1e-14, earlyVoltage: Double = 0)
    -> (collector: Double, base: Double)
{
    let vt = DiodeModel.thermalVoltage
    let forward = `is` * (exp(vbe / vt) - 1), reverse = `is` * (exp(vbc / vt) - 1)
    let early = earlyVoltage > 0 ? 1 - vbc / earlyVoltage : 1
    return ((forward - reverse) * early - reverse, forward / beta + reverse)
}

/// Root of an increasing function on [low, high] by bisection.
private func bisect(_ low: Double, _ high: Double, _ f: (Double) -> Double) -> Double {
    var low = low, high = high
    for _ in 0..<200 {
        let mid = (low + high) / 2
        if f(mid) > 0 { high = mid } else { low = mid }
    }
    return (low + high) / 2
}

@Suite struct BJTTests {
    /// Emitter grounded, V_CE held by a source, and the base fed by a current source.
    private func biased(_ polarity: TransistorParameters.Polarity, vce: Double, ib: Double, earlyVoltage: Double = 0)
        throws -> (vbe: Double, ic: Double, ib: Double, region: BJTModel.Region)
    {
        var parameters = TransistorParameters(polarity: polarity)
        parameters.earlyVoltage = earlyVoltage
        var bench = DeviceBench(.bjt, pins: ["c", "b", "0"], transistor: parameters)
        bench.part(.voltageSource, vce, from: "c", to: "0")
        bench.part(.currentSource, ib, from: "0", to: "b")
        let (result, op) = try bench.operatingPoint()
        #expect(result.netlist.warnings.isEmpty, "\(result.netlist.warnings)")
        let q1 = result.netlist.elements.firstIndex { $0.name == "Q1" }!
        let vbe = op.nodeVoltages[node(result, "b")]
        let model = result.netlist.elements[q1].bjt
        // The current source supplies the base current.
        return (vbe, op.elementCurrents[q1], ib, model.region(vbe: vbe, vbc: vbe - vce))
    }

    @Test(arguments: [0.0, 50.0])
    func forwardActive(earlyVoltage: Double) throws {
        let (vbe, ic, ib, region) = try biased(.n, vce: 5, ib: 10e-6, earlyVoltage: earlyVoltage)
        let expectedVBE = bisect(0, 1) { ebersMoll(vbe: $0, vbc: $0 - 5, earlyVoltage: earlyVoltage).base - 10e-6 }
        let expectedIC = ebersMoll(vbe: expectedVBE, vbc: expectedVBE - 5, earlyVoltage: earlyVoltage).collector
        #expect(abs(vbe - expectedVBE) < 1e-6)
        #expect(abs(ic - expectedIC) < 1e-6 * expectedIC)
        #expect(region == .active)
        if earlyVoltage == 0 {
            #expect(abs(ic / ib - 100) < 1e-3, "β")
        } else {
            // The Early effect raises Ic by about V_CE/V_A.
            #expect(ic / ib > 100 * (1 + 4 / earlyVoltage))
        }
    }

    @Test func pnpMirrorsNPN() throws {
        let npn = try biased(.n, vce: 5, ib: 10e-6)
        let pnp = try biased(.p, vce: -5, ib: -10e-6)
        #expect(abs(pnp.vbe + npn.vbe) < 1e-9)
        #expect(abs(pnp.ic + npn.ic) < 1e-9 * npn.ic)
        #expect(pnp.region == .active)
    }

    @Test func saturatesWhenOverdriven() throws {
        // β·Ib = 43 mA would be far more than the 5 mA that R1 can pass.
        var bench = DeviceBench(.bjt, pins: ["c", "b", "0"])
        bench.part(.voltageSource, 5, from: "vcc", to: "0")
        bench.part(.resistor, 1e3, from: "vcc", to: "c")
        bench.part(.resistor, 10e3, from: "vcc", to: "b")
        let (result, op) = try bench.operatingPoint()
        let vce = op.nodeVoltages[node(result, "c")], vbe = op.nodeVoltages[node(result, "b")]
        let q1 = element(result, "Q1")
        #expect(result.netlist.elements[q1].bjt.region(vbe: vbe, vbc: vbe - vce) == .saturation)
        #expect(vce > 0 && vce < 0.3)
        // KCL: R1 feeds the collector, R2 the base.
        let expected = ebersMoll(vbe: vbe, vbc: vbe - vce)
        #expect(abs(op.elementCurrents[q1] - expected.collector) < 1e-6 * expected.collector)
        #expect(abs(op.elementCurrents[element(result, "R1")] - expected.collector) < 1e-6 * expected.collector)
        #expect(abs(op.elementCurrents[element(result, "R2")] - expected.base) < 1e-6 * expected.base)
    }

    @Test func commonEmitterBiasAndGain() throws {
        var circuit = Examples.commonEmitterAmplifier.circuit
        circuit.simulation.analysis = .operatingPoint
        let dc = try Simulator.run(circuit)
        guard case let .operatingPoint(op) = dc.output else { Issue.record("wrong output"); return }
        // Every element's power sums to zero: the sources deliver what the rest absorbs.
        #expect(abs(op.elementPowers.reduce(0, +)) < 1e-9)
        let ic = op.elementCurrents[element(dc, "Q1")]
        #expect(abs(ic - 1.32e-3) < 0.02e-3, "hand calculation: Ic ≈ 1.32 mA")

        // Small-signal gain −β·RC/(rπ + (β + 1)·RE) with rπ = β·Vt/Ic.
        let rPi = 100 * DiodeModel.thermalVoltage / ic
        let gain = 100 * 4.7e3 / (rPi + 101 * 1e3)
        circuit.simulation.analysis = .ac
        circuit.simulation.startFrequency = 1e3
        circuit.simulation.stopFrequency = 10e3
        let ac = try Simulator.run(circuit)
        guard case let .ac(response) = ac.output else { Issue.record("wrong output"); return }
        let h = response.nodeVoltages[node(ac, "out")][0] / response.nodeVoltages[node(ac, "in")][0]
        #expect(abs(h.magnitude - gain) < 5e-3 * gain)
        #expect(abs(abs(h.phase) - .pi) < 0.01, "inverting")

        // The 0.5 V transient swings the output by about the small-signal gain.
        let transient = try Simulator.run(Examples.commonEmitterAmplifier.circuit)
        guard case let .transient(tr) = transient.output else { Issue.record("wrong output"); return }
        let out = tr.nodeVoltages[node(transient, "out")]
        #expect(abs((out.max()! - out.min()!) / 2 / 0.5 - gain) < 0.03 * gain)
    }
}

@Suite struct MOSFETTests {
    /// Source grounded, with V_GS and V_DS held by sources: returns Id.
    private func drainCurrent(_ polarity: TransistorParameters.Polarity = .n, vgs: Double, vds: Double, lambda: Double = 0) throws -> Double {
        var parameters = TransistorParameters(polarity: polarity)
        parameters.channelLengthModulation = lambda
        var bench = DeviceBench(.mosfet, pins: ["d", "g", "0"], transistor: parameters)
        bench.part(.voltageSource, vgs, from: "g", to: "0")
        bench.part(.voltageSource, vds, from: "d", to: "0")
        let (result, op) = try bench.operatingPoint()
        return op.elementCurrents[element(result, "M1")]
    }

    @Test func squareLawRegions() throws {
        // k = 2 mA/V², Vth = 1 V.
        #expect(abs(try drainCurrent(vgs: 2, vds: 5, lambda: 0.02) - 1e-3 * 1.1) < 1e-10, "saturation")
        #expect(abs(try drainCurrent(vgs: 3, vds: 0.5) - 2e-3 * (2 * 0.5 - 0.125)) < 1e-10, "triode")
        #expect(abs(try drainCurrent(vgs: 0.5, vds: 5)) < 1e-11, "cutoff")
        // With V_DS < 0 the source and drain swap: V_GD = 3.5 V, V_SD = 0.5 V.
        #expect(abs(try drainCurrent(vgs: 3, vds: -0.5) + 2e-3 * (2.5 * 0.5 - 0.125)) < 1e-10, "reversed")
    }

    @Test func pChannelMirrorsNChannel() throws {
        #expect(abs(try drainCurrent(.p, vgs: -2, vds: -5, lambda: 0.02) + 1.1e-3) < 1e-10)
        #expect(abs(try drainCurrent(.p, vgs: -3, vds: -0.5) + 1.75e-3) < 1e-10)
    }

    @Test func commonSourceAmplifier() throws {
        // Gate at 2 V: Id = ½·k·1² = 1 mA, so the drain sits at 10 V − 4 kΩ·1 mA = 6 V; gain −k·V_ov·RD = −8.
        var bench = DeviceBench(.mosfet, pins: ["d", "g", "0"])
        bench.part(.voltageSource, 2, from: "g", to: "0")
        bench.part(.voltageSource, 10, from: "vdd", to: "0")
        bench.part(.resistor, 4e3, from: "vdd", to: "d")
        let (result, op) = try bench.operatingPoint()
        #expect(abs(op.nodeVoltages[node(result, "d")] - 6) < 1e-6)

        var circuit = bench.b.circuit
        circuit.simulation.analysis = .ac
        circuit.simulation.startFrequency = 1e3
        circuit.simulation.stopFrequency = 10e3
        let ac = try Simulator.run(circuit)
        guard case let .ac(response) = ac.output else { Issue.record("wrong output"); return }
        // Both sources have AC magnitude 1. By superposition the drain gets −8 × the gate's, plus the
        // supply's 1 through RD (with λ = 0 the transistor's g_ds is 0, so RD carries it undivided).
        let gate = response.nodeVoltages[node(ac, "g")][0], drain = response.nodeVoltages[node(ac, "d")][0]
        #expect(((drain - Complex(1)) / gate - Complex(-8)).magnitude < 1e-6)
    }

    @Test func cmosInverterTransferCurve() throws {
        let result = try Simulator.run(Examples.cmosInverter.circuit)
        guard case let .transient(tr) = result.output else { Issue.record("wrong output"); return }
        let input = tr.nodeVoltages[node(result, "in")], output = tr.nodeVoltages[node(result, "out")]
        let m1 = tr.elementCurrents[element(result, "M1")], m2 = tr.elementCurrents[element(result, "M2")]
        for i in input.indices {
            // The devices share their drain current: Id(M1) into M1's drain is −Id(M2).
            #expect(abs(m1[i] + m2[i]) < 1e-9)
            if input[i] < 0.9 { #expect(abs(output[i] - 5) < 1e-6) }
            if input[i] > 4.1 { #expect(abs(output[i]) < 1e-6) }
            // Away from the switching point, one device is in the triode region; this is its exact solution.
            if abs(input[i] - 2) < 1e-12 { #expect(abs(output[i] - (3 + 3.squareRoot())) < 1e-6) }
        }
        // The output falls as the input rises.
        let rising = tr.time.indices.filter { tr.time[$0] > 0.2e-3 && tr.time[$0] < 0.6e-3 }
        for (a, b) in zip(rising, rising.dropFirst()) { #expect(output[b] <= output[a] + 1e-9) }
    }
}
