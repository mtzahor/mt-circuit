import Foundation

// MARK: - Component kinds

public enum ComponentKind: String, Codable, CaseIterable, Sendable {
    case resistor
    case capacitor
    case inductor
    case diode
    case bjt
    case mosfet
    case voltageSource
    case currentSource
    case opAmp
    case logicGate
    case ground
    case netLabel

    public var displayName: String {
        switch self {
        case .resistor: "Resistor"
        case .capacitor: "Capacitor"
        case .inductor: "Inductor"
        case .diode: "Diode"
        case .bjt: "BJT"
        case .mosfet: "MOSFET"
        case .voltageSource: "Voltage Source"
        case .currentSource: "Current Source"
        case .opAmp: "Op-Amp"
        case .logicGate: "Logic Gate"
        case .ground: "Ground"
        case .netLabel: "Net Label"
        }
    }

    /// Reference-designator prefix used for automatic naming ("R1", "C2", …).
    public var namePrefix: String {
        switch self {
        case .resistor: "R"
        case .capacitor: "C"
        case .inductor: "L"
        case .diode: "D"
        case .bjt: "Q"
        case .mosfet: "M"
        case .voltageSource: "V"
        case .currentSource: "I"
        case .opAmp, .logicGate: "U"
        case .ground: "GND"
        case .netLabel: "net"
        }
    }

    /// Unit symbol of the component's primary value. A diode's value is its saturation current,
    /// a BJT's its current gain β, a MOSFET's its threshold voltage, an op-amp's its gain, and a
    /// logic gate's its supply voltage.
    public var unitSymbol: String {
        switch self {
        case .resistor: "Ω"
        case .capacitor: "F"
        case .inductor: "H"
        case .voltageSource, .mosfet, .logicGate: "V"
        case .currentSource, .diode: "A"
        case .bjt, .opAmp, .ground, .netLabel: ""
        }
    }

    public var defaultValue: Double {
        switch self {
        case .resistor: 1e3
        case .capacitor: 1e-6
        case .inductor: 1e-3
        case .diode: 1e-14
        case .bjt: 100
        case .mosfet: 1
        case .voltageSource: 5
        case .currentSource: 1e-3
        case .opAmp: 1e5
        case .logicGate: 5
        case .ground, .netLabel: 0
        }
    }

    /// Pin locations relative to the component origin, before rotation.
    /// Two-terminal parts span four grid units horizontally; pin 0 is the
    /// "+" / "from" terminal, or a diode's anode. An op-amp points right: pin 0 is the non-inverting
    /// input (bottom left), pin 1 the inverting input (top left), pin 2 the output. A transistor's
    /// pins are in SPICE order: collector (top right), base (left), emitter (bottom right) for a
    /// BJT; drain, gate, source for a MOSFET. P-type transistors mirror them (see `Component`). A
    /// logic gate points right like an op-amp, with input A (top left), input B (bottom left), and
    /// its output last; a NOT gate has one input, in line with its output (see `Component`).
    public var pinOffsets: [GridPoint] {
        switch self {
        case .ground, .netLabel: [GridPoint(0, 0)]
        case .opAmp: [GridPoint(-2, 1), GridPoint(-2, -1), GridPoint(2, 0)]
        case .logicGate: [GridPoint(-2, -1), GridPoint(-2, 1), GridPoint(2, 0)]
        case .bjt, .mosfet: [GridPoint(1, -2), GridPoint(-2, 0), GridPoint(1, 2)]
        default: [GridPoint(-2, 0), GridPoint(2, 0)]
        }
    }

    /// How messages refer to pin `index` of `count`: "Pin 1", "The anode" of a diode, or "The
    /// output" of an op-amp or logic gate.
    public func pinName(_ index: Int, of count: Int) -> String {
        switch self {
        case .diode: ["The anode", "The cathode"][index]
        case .bjt: ["The collector", "The base", "The emitter"][index]
        case .mosfet: ["The drain", "The gate", "The source"][index]
        case .opAmp: ["The + input", "The − input", "The output"][index]
        case .logicGate where index == count - 1: "The output"
        case .logicGate: count == 2 ? "The input" : ["Input A", "Input B"][index]
        default: "Pin \(index + 1)"
        }
    }

    public var isTransistor: Bool { self == .bjt || self == .mosfet }

    public var isSource: Bool { self == .voltageSource || self == .currentSource }

    /// Whether the component is a circuit element with a value (as opposed to a connectivity marker).
    public var hasValue: Bool { self != .ground && self != .netLabel }

    /// Sources are placed vertically with the "+" terminal on top; everything else horizontally.
    public var defaultRotation: Int { isSource ? 1 : 0 }
}

// MARK: - Source waveforms

/// Time-domain and small-signal description of an independent source.
///
/// The component's `value` is the "main" level: the DC value, the final value of a step,
/// the offset of a sine, or the pulsed value of a pulse train.
public struct SourceWaveform: Codable, Hashable, Sendable {
    public enum Shape: String, Codable, CaseIterable, Sendable {
        case dc, step, sine, pulse

        public var displayName: String {
            switch self {
            case .dc: "DC"
            case .step: "Step"
            case .sine: "Sine"
            case .pulse: "Pulse"
            }
        }
    }

    public var shape: Shape = .dc
    /// Level before the step / between pulses.
    public var initialValue: Double = 0
    public var delay: Double = 0
    public var riseTime: Double = 0
    public var fallTime: Double = 0
    public var pulseWidth: Double = 0.5e-3
    public var period: Double = 1e-3
    public var amplitude: Double = 1
    public var frequency: Double = 1e3
    /// Sine phase in degrees.
    public var phase: Double = 0
    /// Small-signal magnitude used by AC analysis.
    public var acMagnitude: Double = 1
    /// Small-signal phase in degrees used by AC analysis.
    public var acPhase: Double = 0

    public init(shape: Shape = .dc) {
        self.shape = shape
    }

    /// Instantaneous source value at time `t` (seconds) for the given main `level`.
    public func value(at t: Double, level: Double) -> Double {
        switch shape {
        case .dc:
            return level
        case .step:
            if t <= delay { return initialValue }
            if riseTime > 0, t < delay + riseTime {
                return initialValue + (level - initialValue) * (t - delay) / riseTime
            }
            return level
        case .sine:
            let phaseRad = phase * .pi / 180
            let elapsed = max(0, t - delay)
            return level + amplitude * sin(2 * .pi * frequency * elapsed + phaseRad)
        case .pulse:
            if t <= delay { return initialValue }
            var tt = t - delay
            if period > 0 { tt = tt.truncatingRemainder(dividingBy: period) }
            let tr = max(riseTime, 0), tf = max(fallTime, 0), pw = max(pulseWidth, 0)
            if tt < tr { return initialValue + (level - initialValue) * tt / tr }
            if tt < tr + pw { return level }
            if tt < tr + pw + tf { return level + (initialValue - level) * (tt - tr - pw) / tf }
            return initialValue
        }
    }

    /// Short description for the main `level`, e.g. "STEP 0 V→5 V" or "1 V SIN 1 kHz".
    public func summary(level: Double, unit: String) -> String {
        switch shape {
        case .dc:
            return SIFormat.string(level, unit: unit)
        case .step:
            return "STEP \(SIFormat.string(initialValue, unit: unit))→\(SIFormat.string(level, unit: unit))"
        case .sine:
            let offset = level == 0 ? "" : "\(SIFormat.string(level, unit: unit)) + "
            return "\(offset)\(SIFormat.string(amplitude, unit: unit)) SIN \(SIFormat.string(frequency, unit: "Hz"))"
        case .pulse:
            return "PULSE \(SIFormat.string(initialValue, unit: unit))/\(SIFormat.string(level, unit: unit)) \(SIFormat.string(period, unit: "s"))"
        }
    }
}

// MARK: - Transistor parameters

/// A transistor's polarity and its parameters besides its main value (β of a BJT, threshold
/// voltage of a MOSFET). Each field applies to one family; the other family ignores it.
public struct TransistorParameters: Codable, Hashable, Sendable {
    public enum Polarity: String, Codable, CaseIterable, Sendable {
        /// NPN or N-channel.
        case n
        /// PNP or P-channel: the same laws with every voltage and current negated.
        case p
    }

    public var polarity: Polarity = .n
    /// BJT saturation current Is.
    public var saturationCurrent = 1e-14
    /// BJT Early voltage VA; 0 means no Early effect.
    public var earlyVoltage = 0.0
    /// MOSFET transconductance parameter k = µ·Cox·W/L: Id = ½·k·(Vgs − Vth)² in saturation.
    public var transconductance = 2e-3
    /// MOSFET channel-length modulation λ; 0 means none.
    public var channelLengthModulation = 0.0

    public init(polarity: Polarity = .n) {
        self.polarity = polarity
    }

    /// Missing keys take their defaults, so that parameters added later keep older documents readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TransistorParameters()
        polarity = try container.decodeIfPresent(Polarity.self, forKey: .polarity) ?? defaults.polarity
        saturationCurrent = try container.decodeIfPresent(Double.self, forKey: .saturationCurrent) ?? defaults.saturationCurrent
        earlyVoltage = try container.decodeIfPresent(Double.self, forKey: .earlyVoltage) ?? defaults.earlyVoltage
        transconductance = try container.decodeIfPresent(Double.self, forKey: .transconductance) ?? defaults.transconductance
        channelLengthModulation = try container.decodeIfPresent(Double.self, forKey: .channelLengthModulation)
            ?? defaults.channelLengthModulation
    }
}

// MARK: - Schematic objects

public struct Component: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: ComponentKind
    /// Reference designator ("R1"), or the net name for net labels.
    public var name: String
    public var position: GridPoint
    /// Rotation in quarter turns clockwise (0–3).
    public var rotation: Int
    public var value: Double
    public var waveform: SourceWaveform
    /// A diode's emission coefficient n; nil means the default, 1. Optional so that documents
    /// saved before diodes existed still open.
    public var emissionCoefficient: Double?
    /// A transistor's polarity and parameters; nil for other parts.
    public var transistor: TransistorParameters?
    /// A logic gate's function and delay; nil for other parts.
    public var logic: LogicParameters?

    public init(
        id: UUID = UUID(),
        kind: ComponentKind,
        name: String,
        position: GridPoint,
        rotation: Int? = nil,
        value: Double? = nil,
        waveform: SourceWaveform = SourceWaveform(),
        emissionCoefficient: Double? = nil,
        transistor: TransistorParameters? = nil,
        logic: LogicParameters? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        self.rotation = rotation ?? kind.defaultRotation
        self.value = value ?? kind.defaultValue
        self.waveform = waveform
        self.emissionCoefficient = emissionCoefficient
        self.transistor = transistor ?? (kind.isTransistor ? TransistorParameters() : nil)
        self.logic = logic ?? (kind == .logicGate ? LogicParameters() : nil)
    }

    /// Pin locations relative to the origin, before rotation. P-type transistors are drawn upside
    /// down, with the emitter or source on top toward the positive supply, so their pins mirror.
    /// A NOT gate's single input is in line with its output, like a two-terminal part's pins.
    public var pinOffsets: [GridPoint] {
        if kind == .logicGate, logic?.function.inputCount == 1 { return [GridPoint(-2, 0), GridPoint(2, 0)] }
        guard kind.isTransistor, transistor?.polarity == .p else { return kind.pinOffsets }
        return kind.pinOffsets.map { GridPoint($0.x, -$0.y) }
    }

    /// Absolute grid positions of the component's pins.
    public var pinPositions: [GridPoint] {
        pinOffsets.map { position + $0.rotated(by: rotation) }
    }

    /// Human-readable value, e.g. "4.7 kΩ", "SIN 1 V 1 kHz", "A = 100k", "Is = 10 fA", or "NAND".
    public var valueDescription: String {
        guard kind.hasValue else { return "" }
        if kind == .opAmp { return "A = \(SIFormat.compact(value))" }
        if kind == .logicGate {
            let parameters = logic ?? LogicParameters()
            var parts = [parameters.function.displayName]
            if value != kind.defaultValue { parts.append(SIFormat.string(value, unit: "V")) }
            if parameters.delay != LogicParameters.defaultDelay { parts.append("tpd = \(SIFormat.string(parameters.delay, unit: "s"))") }
            return parts.joined(separator: ", ")
        }
        if kind == .diode {
            let current = "Is = \(SIFormat.string(value, unit: "A"))"
            guard let n = emissionCoefficient, n != 1 else { return current }
            return current + ", n = \(SIFormat.compact(n))"
        }
        let parameters = transistor ?? TransistorParameters()
        if kind == .bjt {
            let gain = "β = \(SIFormat.compact(value))"
            guard parameters.earlyVoltage > 0 else { return gain }
            return gain + ", VA = \(SIFormat.string(parameters.earlyVoltage, unit: "V"))"
        }
        if kind == .mosfet {
            return "Vth = \(SIFormat.string(value, unit: "V")), k = \(SIFormat.string(parameters.transconductance, unit: "A/V²"))"
        }
        let unit = kind.unitSymbol
        guard kind.isSource else { return SIFormat.string(value, unit: unit) }
        return waveform.summary(level: value, unit: unit)
    }
}

public struct Wire: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: GridPoint
    public var end: GridPoint

    public init(id: UUID = UUID(), start: GridPoint, end: GridPoint) {
        self.id = id
        self.start = start
        self.end = end
    }
}

// MARK: - Simulation settings

public struct SimulationSettings: Codable, Hashable, Sendable {
    public enum Analysis: String, Codable, CaseIterable, Sendable {
        case operatingPoint, transient, ac

        public var displayName: String {
            switch self {
            case .operatingPoint: "DC Operating Point"
            case .transient: "Transient"
            case .ac: "AC Sweep"
            }
        }
    }

    public enum InitialConditions: String, Codable, CaseIterable, Sendable {
        /// Capacitors discharged and inductors de-energized at t = 0.
        case zero
        /// Start from the DC operating point with sources at their t = 0 values.
        case operatingPoint

        public var displayName: String {
            switch self {
            case .zero: "From rest"
            case .operatingPoint: "From DC op. point"
            }
        }
    }

    public enum IntegrationMethod: String, Codable, CaseIterable, Sendable {
        case trapezoidal, backwardEuler

        public var displayName: String {
            switch self {
            case .trapezoidal: "Trapezoidal"
            case .backwardEuler: "Backward Euler"
            }
        }
    }

    public var analysis: Analysis = .transient
    public var stopTime: Double = 10e-3
    /// Fixed time step; 0 means automatic (stop time / 2000).
    public var timeStep: Double = 0
    public var initialConditions: InitialConditions = .zero
    public var integrationMethod: IntegrationMethod = .trapezoidal
    public var startFrequency: Double = 1
    public var stopFrequency: Double = 1e6
    public var pointsPerDecade: Int = 50

    public init() {}

    public var effectiveTimeStep: Double {
        timeStep > 0 ? timeStep : stopTime / 2000
    }
}

// MARK: - Circuit

public struct Circuit: Codable, Hashable, Sendable {
    public var formatVersion: Int = 1
    public var components: [Component] = []
    public var wires: [Wire] = []
    public var simulation = SimulationSettings()
    /// ID of the tutorial lesson this circuit is the learner's work on (see `Tutorial`), or nil
    /// for an ordinary schematic. Optional so that documents saved before the tutorial still open.
    public var lesson: String?

    public init(components: [Component] = [], wires: [Wire] = [], simulation: SimulationSettings = SimulationSettings()) {
        self.components = components
        self.wires = wires
        self.simulation = simulation
    }

    public var isEmpty: Bool { components.isEmpty && wires.isEmpty }

    public func component(withID id: UUID) -> Component? {
        components.first { $0.id == id }
    }

    /// The next free reference designator for `kind`, e.g. "R3".
    public func nextName(for kind: ComponentKind) -> String {
        switch kind {
        case .ground: return "GND"
        case .netLabel:
            let used = Set(components.filter { $0.kind == .netLabel }.map(\.name))
            var n = 1
            while used.contains("net\(n)") { n += 1 }
            return "net\(n)"
        default:
            let prefix = kind.namePrefix
            let used = Set(components.map(\.name))
            var n = 1
            while used.contains("\(prefix)\(n)") { n += 1 }
            return "\(prefix)\(n)"
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> Circuit {
        try JSONDecoder().decode(Circuit.self, from: data)
    }
}
