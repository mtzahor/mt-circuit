import Foundation

/// Ready-made circuits shown in the app's Examples menu.
public enum Examples {
    public struct Example: Sendable {
        public var name: String
        public var circuit: Circuit
    }

    public static var all: [Example] {
        [
            voltageDivider, rcStep, rcLowPass, rlPulse, seriesRLC, parallelRLC,
            halfWaveRectifier, diodeClipper, commonEmitterAmplifier, cmosInverter, invertingAmplifier, sallenKeyLowPass,
        ]
    }

    // MARK: - Layout helpers

    /// Builds the common "source on the left, ladder to the right" layout.
    private struct Sketch {
        var circuit = Circuit()
        let top = 6, bottom = 12

        mutating func add(_ kind: ComponentKind, _ name: String, _ value: Double, at position: GridPoint, rotation: Int, waveform: SourceWaveform = SourceWaveform()) {
            circuit.components.append(Component(kind: kind, name: name, position: position, rotation: rotation, value: value, waveform: waveform))
        }
        /// Two-terminal part along the top rail, with pin 1 at column `x`.
        mutating func series(_ kind: ComponentKind, _ name: String, _ value: Double, x: Int) {
            add(kind, name, value, at: GridPoint(x + 2, top), rotation: 0)
        }
        /// Vertical part from the top rail down, with its top pin at column `x`.
        mutating func shunt(_ kind: ComponentKind, _ name: String, _ value: Double, x: Int, waveform: SourceWaveform = SourceWaveform()) {
            add(kind, name, value, at: GridPoint(x, top + 2), rotation: 1, waveform: waveform)
            if top + 4 < bottom { wire(GridPoint(x, top + 4), GridPoint(x, bottom)) }
        }
        mutating func wire(_ a: GridPoint, _ b: GridPoint) {
            circuit.wires.append(Wire(start: a, end: b))
        }
        mutating func topWire(_ x1: Int, _ x2: Int) { wire(GridPoint(x1, top), GridPoint(x2, top)) }
        mutating func label(_ name: String, x: Int) {
            label(name, at: GridPoint(x, top))
        }
        mutating func label(_ name: String, at point: GridPoint) {
            add(.netLabel, name, 0, at: point, rotation: 0)
        }
        /// A transistor with its origin at `position`, control pin two columns left of it. An N-type
        /// device has its collector or drain at position + (1, −2); a P-type one, its emitter or source.
        mutating func transistor(_ kind: ComponentKind, _ name: String, _ polarity: TransistorParameters.Polarity = .n, at position: GridPoint) {
            circuit.components.append(Component(
                kind: kind, name: name, position: position, rotation: 0, transistor: TransistorParameters(polarity: polarity)))
        }
        mutating func ground(at point: GridPoint) {
            add(.ground, "GND", 0, at: point, rotation: 0)
        }
        /// Op-amp pointing right with its + input (bottom left) at `plus`: the − input is
        /// two rows up and the output is at plus + (4, −1).
        mutating func opAmp(_ name: String, plus: GridPoint) {
            add(.opAmp, name, ComponentKind.opAmp.defaultValue, at: plus + GridPoint(2, -1), rotation: 0)
        }
        mutating func groundRail(from x1: Int, to x2: Int) {
            wire(GridPoint(x1, bottom), GridPoint(x2, bottom))
            add(.ground, "GND", 0, at: GridPoint(x1, bottom), rotation: 0)
        }
    }

    private static func source(_ shape: SourceWaveform.Shape, _ configure: (inout SourceWaveform) -> Void = { _ in }) -> SourceWaveform {
        var w = SourceWaveform(shape: shape)
        configure(&w)
        return w
    }

    // MARK: - Examples

    public static var voltageDivider: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 10, x: 6)
        s.topWire(6, 10)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 20)
        s.label("out", x: 17)
        s.shunt(.resistor, "R2", 2e3, x: 20)
        s.groundRail(from: 6, to: 20)
        s.circuit.simulation.analysis = .operatingPoint
        return Example(name: "Voltage Divider", circuit: s.circuit)
    }

    public static var rcStep: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 5, x: 6, waveform: source(.step))
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 20)
        s.label("out", x: 17)
        s.shunt(.capacitor, "C1", 1e-6, x: 20)
        s.groundRail(from: 6, to: 20)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 5e-3
        return Example(name: "RC Charging (Step Response)", circuit: s.circuit)
    }

    public static var rcLowPass: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 1; $0.frequency = 1e3 })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 20)
        s.label("out", x: 17)
        s.shunt(.capacitor, "C1", 100e-9, x: 20)
        s.groundRail(from: 6, to: 20)
        s.circuit.simulation.analysis = .ac
        s.circuit.simulation.startFrequency = 10
        s.circuit.simulation.stopFrequency = 1e6
        s.circuit.simulation.stopTime = 5e-3
        return Example(name: "RC Low-Pass Filter", circuit: s.circuit)
    }

    public static var rlPulse: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 5, x: 6, waveform: source(.pulse) {
            $0.initialValue = 0
            $0.pulseWidth = 1e-3
            $0.period = 2e-3
        })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 100, x: 10)
        s.topWire(14, 20)
        s.label("out", x: 17)
        s.shunt(.inductor, "L1", 10e-3, x: 20)
        s.groundRail(from: 6, to: 20)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 4e-3
        return Example(name: "RL Circuit (Pulse Response)", circuit: s.circuit)
    }

    public static var seriesRLC: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 1, x: 6, waveform: source(.step))
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 20, x: 10)
        s.topWire(14, 16)
        s.series(.inductor, "L1", 1e-3, x: 16)
        s.topWire(20, 26)
        s.label("out", x: 23)
        s.shunt(.capacitor, "C1", 1e-6, x: 26)
        s.groundRail(from: 6, to: 26)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 2e-3
        s.circuit.simulation.timeStep = 0.5e-6
        return Example(name: "Series RLC (Underdamped Step)", circuit: s.circuit)
    }

    public static var parallelRLC: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 1; $0.frequency = 5e3 })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 26)
        s.label("out", x: 17)
        s.shunt(.inductor, "L1", 1e-3, x: 20)
        s.shunt(.capacitor, "C1", 1e-6, x: 26)
        s.groundRail(from: 6, to: 26)
        s.circuit.simulation.analysis = .ac
        s.circuit.simulation.startFrequency = 100
        s.circuit.simulation.stopFrequency = 100e3
        s.circuit.simulation.pointsPerDecade = 100
        return Example(name: "Parallel RLC (Band-Pass)", circuit: s.circuit)
    }

    /// D1 charges C1 to near the peak of each cycle; between peaks C1 discharges into R1.
    public static var halfWaveRectifier: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 5; $0.frequency = 50 })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.diode, "D1", ComponentKind.diode.defaultValue, x: 10)
        s.topWire(14, 26)
        s.label("out", x: 17)
        s.shunt(.capacitor, "C1", 100e-6, x: 20)
        s.shunt(.resistor, "R1", 1e3, x: 26)
        s.groundRail(from: 6, to: 26)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 100e-3
        return Example(name: "Half-Wave Rectifier", circuit: s.circuit)
    }

    /// Antiparallel diodes limit the output to about ±0.7 V: D1 conducts on positive peaks, D2 on negative ones.
    public static var diodeClipper: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 3; $0.frequency = 1e3 })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 26)
        s.label("out", x: 17)
        s.shunt(.diode, "D1", ComponentKind.diode.defaultValue, x: 20)
        // Anode at the bottom, so D2 conducts when the output is negative.
        s.add(.diode, "D2", ComponentKind.diode.defaultValue, at: GridPoint(26, s.top + 2), rotation: 3)
        s.wire(GridPoint(26, s.top + 4), GridPoint(26, s.bottom))
        s.groundRail(from: 6, to: 26)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 2e-3
        return Example(name: "Diode Clipper", circuit: s.circuit)
    }

    /// Voltage-divider bias sets Ic ≈ 1.3 mA; the emitter resistor makes the gain about −RC/RE ≈ −4.6.
    public static var commonEmitterAmplifier: Example {
        var s = Sketch()
        s.add(.voltageSource, "V1", 0, at: GridPoint(6, 13), rotation: 1, waveform: source(.sine) { $0.amplitude = 0.5; $0.frequency = 1e3 })
        s.wire(GridPoint(6, 11), GridPoint(10, 11))
        s.label("in", at: GridPoint(8, 11))
        s.wire(GridPoint(6, 15), GridPoint(6, 21))
        s.add(.capacitor, "C1", 10e-6, at: GridPoint(12, 11), rotation: 0)
        s.wire(GridPoint(14, 11), GridPoint(16, 11))
        // Bias divider from the supply rail (y = 3) to ground (y = 21), tapped for the base at (16, 11).
        s.add(.resistor, "R1", 47e3, at: GridPoint(16, 5), rotation: 1)
        s.wire(GridPoint(16, 7), GridPoint(16, 13))
        s.add(.resistor, "R2", 10e3, at: GridPoint(16, 15), rotation: 1)
        s.wire(GridPoint(16, 17), GridPoint(16, 21))
        s.wire(GridPoint(16, 11), GridPoint(18, 11))
        s.transistor(.bjt, "Q1", at: GridPoint(20, 11))
        s.add(.resistor, "R3", 4.7e3, at: GridPoint(21, 5), rotation: 1)
        s.wire(GridPoint(21, 7), GridPoint(21, 9))
        s.wire(GridPoint(21, 8), GridPoint(24, 8))
        s.label("out", at: GridPoint(24, 8))
        s.add(.resistor, "R4", 1e3, at: GridPoint(21, 17), rotation: 1)
        s.wire(GridPoint(21, 13), GridPoint(21, 15))
        s.wire(GridPoint(21, 19), GridPoint(21, 21))
        s.wire(GridPoint(16, 3), GridPoint(28, 3))
        // A supply is an AC ground: no small-signal voltage in an AC sweep.
        s.add(.voltageSource, "V2", 12, at: GridPoint(28, 5), rotation: 1, waveform: source(.dc) { $0.acMagnitude = 0 })
        s.wire(GridPoint(28, 7), GridPoint(28, 21))
        s.wire(GridPoint(6, 21), GridPoint(28, 21))
        s.ground(at: GridPoint(6, 21))
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.initialConditions = .operatingPoint
        s.circuit.simulation.stopTime = 3e-3
        return Example(name: "BJT Common-Emitter Amplifier", circuit: s.circuit)
    }

    /// The input ramps slowly, so the output traces the inverter's transfer curve: high while the
    /// NMOS M1 is off, low once it is on and the PMOS M2 is off.
    public static var cmosInverter: Example {
        var s = Sketch()
        s.add(.voltageSource, "V1", 5, at: GridPoint(6, 12), rotation: 1, waveform: source(.pulse) {
            $0.initialValue = 0
            $0.delay = 0.2e-3
            $0.riseTime = 0.4e-3
            $0.pulseWidth = 0.4e-3
            $0.fallTime = 0.4e-3
            $0.period = 2e-3
        })
        s.wire(GridPoint(6, 10), GridPoint(16, 10))
        s.label("in", at: GridPoint(10, 10))
        s.wire(GridPoint(6, 14), GridPoint(6, 17))
        // Gates tied together at x = 16; drains tied together at x = 21.
        s.transistor(.mosfet, "M2", .p, at: GridPoint(20, 7))
        s.transistor(.mosfet, "M1", at: GridPoint(20, 13))
        s.wire(GridPoint(18, 7), GridPoint(16, 7))
        s.wire(GridPoint(16, 7), GridPoint(16, 13))
        s.wire(GridPoint(16, 13), GridPoint(18, 13))
        s.wire(GridPoint(21, 9), GridPoint(21, 11))
        s.wire(GridPoint(21, 10), GridPoint(25, 10))
        s.label("out", at: GridPoint(25, 10))
        s.wire(GridPoint(21, 15), GridPoint(21, 17))
        s.wire(GridPoint(21, 5), GridPoint(21, 3))
        s.wire(GridPoint(21, 3), GridPoint(32, 3))
        s.add(.voltageSource, "V2", 5, at: GridPoint(32, 5), rotation: 1, waveform: source(.dc) { $0.acMagnitude = 0 })
        s.wire(GridPoint(32, 7), GridPoint(32, 17))
        s.wire(GridPoint(6, 17), GridPoint(32, 17))
        s.ground(at: GridPoint(6, 17))
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 2e-3
        return Example(name: "CMOS Inverter", circuit: s.circuit)
    }

    /// Gain −R2/R1 = −10. The − input sits on the top rail; R2 feeds the output back above U1.
    public static var invertingAmplifier: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 0.5; $0.frequency = 1e3 })
        s.topWire(6, 10)
        s.label("in", x: 8)
        s.series(.resistor, "R1", 1e3, x: 10)
        s.topWire(14, 18)
        s.opAmp("U1", plus: GridPoint(18, 8))
        s.wire(GridPoint(18, 8), GridPoint(18, 12))
        s.wire(GridPoint(16, 6), GridPoint(16, 2))
        s.add(.resistor, "R2", 10e3, at: GridPoint(18, 2), rotation: 0)
        s.wire(GridPoint(20, 2), GridPoint(24, 2))
        s.wire(GridPoint(24, 2), GridPoint(24, 7))
        s.wire(GridPoint(22, 7), GridPoint(28, 7))
        s.label("out", at: GridPoint(26, 7))
        s.groundRail(from: 6, to: 18)
        s.circuit.simulation.analysis = .transient
        s.circuit.simulation.stopTime = 3e-3
        return Example(name: "Op-Amp Inverting Amplifier", circuit: s.circuit)
    }

    /// Unity-gain Sallen–Key low-pass: f0 = 1/(2π·R·√(C1·C2)) ≈ 1.07 kHz, Q = ½·√(C1/C2) ≈ 0.74.
    public static var sallenKeyLowPass: Example {
        var s = Sketch()
        s.shunt(.voltageSource, "V1", 0, x: 6, waveform: source(.sine) { $0.amplitude = 1; $0.frequency = 1e3 })
        s.topWire(6, 8)
        s.label("in", x: 7)
        s.series(.resistor, "R1", 10e3, x: 8)
        s.series(.resistor, "R2", 10e3, x: 12)
        s.topWire(16, 20)
        s.shunt(.capacitor, "C2", 10e-9, x: 18)
        s.opAmp("U1", plus: GridPoint(20, 6))
        // C1 feeds the output back to the R1–R2 junction; the − input ties to the output for unity gain.
        s.wire(GridPoint(12, 6), GridPoint(12, 2))
        s.add(.capacitor, "C1", 22e-9, at: GridPoint(14, 2), rotation: 0)
        s.wire(GridPoint(16, 2), GridPoint(26, 2))
        s.wire(GridPoint(20, 4), GridPoint(20, 2))
        s.wire(GridPoint(26, 2), GridPoint(26, 5))
        s.wire(GridPoint(24, 5), GridPoint(30, 5))
        s.label("out", at: GridPoint(28, 5))
        s.groundRail(from: 6, to: 18)
        s.circuit.simulation.analysis = .ac
        s.circuit.simulation.startFrequency = 10
        s.circuit.simulation.stopFrequency = 100e3
        s.circuit.simulation.stopTime = 5e-3
        return Example(name: "Sallen–Key Low-Pass Filter", circuit: s.circuit)
    }
}
