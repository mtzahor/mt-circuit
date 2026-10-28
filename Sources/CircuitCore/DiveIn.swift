import Foundation

// MARK: - Topics

/// A page of Dive In: what is inside a part, or how one of the building blocks inside a part
/// works. Topics link to deeper ones, from the op-amp down to the pn junction.
public struct DiveInTopic: Identifiable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case parts = "Parts"
        case buildingBlocks = "Building Blocks"
    }

    public var id: String
    public var category: Category
    public var title: String
    /// One line under the title.
    public var headline: String
    /// The picture at the top of the page.
    public var figure: DiveInFigure
    public var sections: [DiveInSection]
    /// Topics about what this one is made of.
    public var deeper: [String]
    /// A working circuit to open and simulate.
    public var circuit: Circuit?
    /// ID of the tutorial lesson about this part.
    public var lesson: String?
}

/// A part of a topic's explanation.
public struct DiveInSection: Sendable {
    public var heading: String?
    /// Paragraphs in the format of `Lesson.introduction`. A link to `divein:<id>` leads to another topic.
    public var text: String
    /// Index of the region of the topic's schematic figure that the section is about.
    public var region: Int?
    /// A figure after the text.
    public var figure: DiveInFigure?

    public init(_ heading: String?, region: Int? = nil, figure: DiveInFigure? = nil, _ text: String) {
        self.heading = heading
        self.text = text
        self.region = region
        self.figure = figure
    }
}

public enum DiveInFigure: Sendable {
    /// A schematic with outlined groups of parts.
    case schematic(Circuit, regions: [SchematicRegion])
    /// A drawing of the physics, made by the app.
    case illustration(Illustration)
}

public enum Illustration: String, Sendable {
    case resistor, capacitor, inductor
    /// A pn junction, without bias or with forward or reverse bias.
    case pnJunction
    /// A diode's current against its voltage.
    case diodeCurve
    /// Electrons crossing the base of an NPN transistor.
    case bjt
    /// An n-channel MOSFET, with a gate voltage that opens its channel.
    case mosfet
}

/// A titled group of parts in a schematic figure, such as the input stage of an op-amp.
public struct SchematicRegion: Sendable, Hashable {
    public var title: String
    /// Names of the parts in the group.
    public var parts: [String]

    public init(_ title: String, parts: [String]) {
        self.title = title
        self.parts = parts
    }
}

// MARK: - Catalog

/// The Dive In topics.
public enum DiveIn {
    public static let urlScheme = "divein"

    public static let topics: [DiveInTopic] = [
        resistor, capacitor, inductor, diode, bjt, mosfet, voltageSource, currentSource, opAmp,
        differentialPair, currentMirror, pushPull,
    ]

    public static func topic(withID id: String) -> DiveInTopic? {
        topics.first { $0.id == id }
    }

    /// The topic about parts of `kind`; nil for grounds and net labels.
    public static func topic(for kind: ComponentKind) -> DiveInTopic? {
        let id: String? = switch kind {
        case .resistor: "resistor"
        case .capacitor: "capacitor"
        case .inductor: "inductor"
        case .diode: "diode"
        case .bjt: "bjt"
        case .mosfet: "mosfet"
        case .voltageSource: "voltage-source"
        case .currentSource: "current-source"
        case .opAmp: "op-amp"
        case .ground, .netLabel: nil
        }
        return id.flatMap(topic(withID:))
    }

    /// The topic a `divein:<id>` link leads to.
    public static func topic(for url: URL) -> DiveInTopic? {
        guard url.scheme == urlScheme else { return nil }
        return topic(withID: String(url.absoluteString.dropFirst(urlScheme.count + 1)))
    }

    /// The topics that `id` is part of: those that list it as a deeper topic.
    public static func containers(of id: String) -> [DiveInTopic] {
        topics.filter { $0.deeper.contains(id) }
    }

    // MARK: Parts

    static var resistor: DiveInTopic {
        DiveInTopic(
            id: "resistor", category: .parts, title: "Resistor",
            headline: "Electrons pushing through a crowd of atoms",
            figure: .illustration(.resistor),
            sections: [
                DiveInSection("What resists", """
                    A resistor is a material that conducts, but not very well. The voltage across it pushes \
                    its free electrons along, and they keep colliding with the vibrating atoms, losing the \
                    energy they picked up. The result is a steady drift, with a current proportional to \
                    the voltage: Ohm's law.

                    > V = I · R

                    The drift is slow, often well under a millimeter per second. The current still starts \
                    everywhere at once, because the push travels through the material at nearly the speed of light.
                    """),
                DiveInSection("Material and shape", """
                    Resistance depends on the material's **resistivity** ρ and on the resistor's shape:

                    > R = ρ · L / A

                    A longer path means more collisions; a wider one lets more electrons through side by \
                    side. Copper's resistivity is tiny, which is why wires barely resist. Resistors use films \
                    of carbon or metal alloys with a far higher resistivity, and a spiral groove cut into the \
                    film lengthens the path until the resistance is right.
                    """),
                DiveInSection("Where the energy goes", """
                    Every collision turns electrical energy into heat, at a rate of P = V · I = I² · R. \
                    That's why resistors have power ratings, ¼ W for a common one, and why a heater is \
                    just a large resistor.
                    """),
                DiveInSection("In MT Circuit", """
                    A resistor follows Ohm's law exactly, at any power and any frequency.
                    """),
            ],
            deeper: [], lesson: "ohms-law")
    }

    static var capacitor: DiveInTopic {
        DiveInTopic(
            id: "capacitor", category: .parts, title: "Capacitor",
            headline: "Two plates and the gap between them",
            figure: .illustration(.capacitor),
            sections: [
                DiveInSection("Charge on the plates", """
                    A capacitor is two conductors, the plates, separated by an insulator, the **dielectric**. \
                    No current crosses the gap. Instead, charge piles up: electrons flowing in collect on one \
                    plate, and as many leave the other, which is left positive. Current seems to flow \
                    through the capacitor, but none crosses it.

                    The charge is proportional to the voltage between the plates:

                    > Q = C · V
                    """),
                DiveInSection("What sets the capacitance", """
                    > C = ε · A / d

                    Larger plates hold more charge at the same voltage, and a thinner gap lets each plate's \
                    charge attract more onto the other. The dielectric's permittivity ε multiplies the \
                    effect: the ceramics in ceramic capacitors have a permittivity thousands of times that \
                    of a vacuum, and electrolytic capacitors use an extremely thin oxide film as their gap.
                    """),
                DiveInSection("Energy in the field", """
                    The separated charges create an electric field in the gap, and the field stores energy: \
                    ½ · C · V². Charging takes current over time, so a capacitor's voltage can't jump:

                    > i = C · dv/dt

                    That is the origin of every RC time constant.
                    """),
                DiveInSection("In MT Circuit", """
                    A capacitor is ideal: it has no leakage and no series resistance.
                    """),
            ],
            deeper: [], lesson: "rc-time-constant")
    }

    static var inductor: DiveInTopic {
        DiveInTopic(
            id: "inductor", category: .parts, title: "Inductor",
            headline: "A coil that stores energy in its magnetic field",
            figure: .illustration(.inductor),
            sections: [
                DiveInSection("Current makes a field", """
                    A current through a wire creates a magnetic field around it. Wind the wire into a coil \
                    and the fields of all the turns add up inside it.
                    """),
                DiveInSection("The field pushes back", """
                    When the current changes, so does the field, and a changing magnetic field induces a \
                    voltage in the coil itself (Faraday's law). That voltage opposes the change (Lenz's law):

                    > v = L · di/dt

                    So an inductor's current can't jump, just as a capacitor's voltage can't. The energy \
                    stored in the field is ½ · L · I².
                    """),
                DiveInSection("What sets the inductance", """
                    For a long coil,

                    > L = µ · N² · A / ℓ

                    The number of turns N counts twice: each turn adds to the field, and the field passes \
                    through every turn. A core of iron or ferrite raises the permeability µ by hundreds to \
                    thousands of times, so a small part can have a large inductance.
                    """),
                DiveInSection("In MT Circuit", """
                    An inductor is ideal: its wire has no resistance and its core never saturates.
                    """),
            ],
            deeper: [], lesson: "inductors")
    }

    static var diode: DiveInTopic {
        DiveInTopic(
            id: "diode", category: .parts, title: "Diode",
            headline: "Inside: a pn junction",
            figure: .illustration(.pnJunction),
            sections: [
                DiveInSection("Doping silicon", """
                    Pure silicon barely conducts: each atom shares its four outer electrons with its \
                    neighbors, and few are free to move. **Doping** changes that. A trace of phosphorus, \
                    with five outer electrons, leaves one electron free per atom: **n-type** silicon. Boron, \
                    with three, leaves a gap that neighboring electrons can hop into. That gap, a **hole**, \
                    moves around like a positive charge: **p-type** silicon.
                    """),
                DiveInSection("The junction", """
                    Join p-type to n-type silicon and free electrons near the boundary diffuse across and \
                    fill holes on the other side. That leaves a thin **depletion region** with no free \
                    carriers, only the fixed, charged atoms: negative on the p side, positive on the n side. \
                    Their electric field pushes back against more diffusion, until a barrier of several \
                    tenths of a volt stops it.
                    """),
                DiveInSection("Forward and reverse", figure: .illustration(.diodeCurve), """
                    Make the p side, the **anode**, more positive than the n side, the **cathode**, and the \
                    barrier shrinks. Carriers flood across and the current rises exponentially with the \
                    voltage, so a silicon diode conducts in earnest from about 0.6 V. Reverse the voltage and \
                    the depletion region widens: only a tiny leakage, the saturation current Is, gets through. \
                    Try the bias buttons above.

                    > I = Is · (e^(V / n·Vt) − 1)
                    """),
                DiveInSection("In MT Circuit", """
                    Diodes follow this Shockley equation. Real diodes also break down at a high enough \
                    reverse voltage (Zener diodes are made to), and their depletion region acts as a small \
                    capacitor; the model leaves both out.
                    """),
            ],
            deeper: [], lesson: "diode")
    }

    static var bjt: DiveInTopic {
        DiveInTopic(
            id: "bjt", category: .parts, title: "BJT",
            headline: "Two pn junctions back to back, with a very thin middle",
            figure: .illustration(.bjt),
            sections: [
                DiveInSection("An n-p-n sandwich", """
                    An NPN bipolar junction transistor is a thin layer of p-type silicon, the **base**, \
                    between two n-type regions: the heavily doped **emitter** and the **collector**. That \
                    makes two [pn junctions](divein:diode) back to back, but it isn't two diodes: \
                    everything depends on the base being very thin, often less than a micrometer.
                    """),
                DiveInSection("Electrons cross the base", """
                    Forward-bias the base–emitter junction, by about 0.7 V, and the emitter injects \
                    electrons into the base. The base is so thin that nearly all of them reach the \
                    collector junction before they meet a hole, and the collector's higher voltage sweeps \
                    them in. Only a few recombine in the base; replacing the holes they use up is the \
                    base current.
                    """),
                DiveInSection("Current gain", """
                    The fraction that makes it across is fixed by the transistor's construction, so the \
                    collector current is a fixed multiple of the base current:

                    > Ic = β · Ib

                    β is typically between 50 and 300. Like a diode's current, Ic grows exponentially with \
                    the base–emitter voltage: every 60 mV more multiplies it by ten.

                    A PNP transistor is the same with p and n swapped, and all its currents and voltages reversed.
                    """),
                DiveInSection("In MT Circuit", """
                    BJTs follow the Ebers–Moll model, with the Early effect but without the capacitances \
                    of the junctions.
                    """),
            ],
            deeper: ["diode"], lesson: "transistor-switch")
    }

    static var mosfet: DiveInTopic {
        DiveInTopic(
            id: "mosfet", category: .parts, title: "MOSFET",
            headline: "A gate that opens a channel with an electric field",
            figure: .illustration(.mosfet),
            sections: [
                DiveInSection("Structure", """
                    An n-channel MOSFET has two n-type islands, the **source** and the **drain**, in a \
                    p-type body. Between them, on the surface, sits the **gate**: a conductor insulated \
                    from the silicon by a layer of oxide only nanometers thick. From source to drain, the \
                    silicon is n-p-n: two [pn junctions](divein:diode) back to back, so normally no current flows.
                    """),
                DiveInSection("The channel", """
                    Raise the gate voltage and its electric field, acting through the oxide, pushes holes \
                    away from the surface and draws electrons to it. Above the **threshold voltage** Vth, \
                    the surface becomes a thin layer of n-type silicon, a **channel** joining source and \
                    drain. Drag the gate voltage above to watch it form.
                    """),
                DiveInSection("Controlled by voltage", """
                    The gate is insulated, so it draws no steady current: a MOSFET is controlled by voltage \
                    alone. The further the gate is above the threshold, the more electrons the channel \
                    holds, and in saturation

                    > Id = ½ · k · (VGS − Vth)²

                    Billions of these switches, in complementary pairs of n- and p-channel devices, make \
                    up every modern chip.
                    """),
                DiveInSection("In MT Circuit", """
                    MOSFETs follow the square law with the body tied to the source, and without capacitances.
                    """),
            ],
            deeper: ["diode"], lesson: "mosfet")
    }

    static var voltageSource: DiveInTopic {
        let circuit = DiveInCircuits.battery
        return DiveInTopic(
            id: "voltage-source", category: .parts, title: "Voltage Source",
            headline: "An ideal source, and what a real one adds",
            figure: .schematic(circuit, regions: [SchematicRegion("Battery", parts: ["V1", "Rint"])]),
            sections: [
                DiveInSection("Ideal", """
                    An ideal voltage source keeps its voltage whatever current it delivers. Inside a real \
                    one, something pumps charge uphill: a chemical reaction, a generator, or a regulator circuit.
                    """),
                DiveInSection("A battery", """
                    In a battery, chemical reactions at the two electrodes release electrons at the negative \
                    terminal and absorb them at the positive one. The chemistry sets the voltage: about 1.5 V \
                    for an alkaline cell and 3.7 V for a lithium-ion one. A 9 V battery is six small cells in series.
                    """),
                DiveInSection("Internal resistance", region: 0, """
                    Real sources sag under load. A simple model is an ideal source in series with a small \
                    **internal resistance** Rint: the more current the load RL draws, the more voltage is \
                    lost inside.

                    > Vout = V · RL / (RL + Rint)

                    Open the circuit and lower RL to watch V(out) droop.
                    """),
            ],
            deeper: [], circuit: circuit)
    }

    static var currentSource: DiveInTopic {
        let circuit = DiveInCircuits.transistorCurrentSource
        return DiveInTopic(
            id: "current-source", category: .parts, title: "Current Source",
            headline: "Holding the current steady, whatever the load",
            figure: .schematic(circuit, regions: []),
            sections: [
                DiveInSection("Ideal", """
                    An ideal current source delivers its current into any load, adjusting its voltage to \
                    suit. Nothing in nature works that way, but a transistor comes close.
                    """),
                DiveInSection("Built from a transistor", """
                    A [BJT](divein:bjt)'s collector current hardly depends on its collector voltage. Fix its \
                    base voltage with the divider R1–R2, add the emitter resistor RE, and the emitter settles \
                    about 0.7 V below the base. That fixes the current through RE, and so through the load RL:

                    > I ≈ (VB − 0.7 V) / RE

                    Open the circuit and change RL: the current stays at about 1 mA.
                    """),
                DiveInSection("Compliance", """
                    It works only while the transistor stays out of saturation, so here RL can go up to \
                    about 10 kΩ. That range is the source's **compliance**. Inside chips, current sources are \
                    usually [current mirrors](divein:current-mirror).
                    """),
            ],
            deeper: ["current-mirror", "bjt"], circuit: circuit)
    }

    static var opAmp: DiveInTopic {
        DiveInTopic(
            id: "op-amp", category: .parts, title: "Op-Amp",
            headline: "Three transistor stages inside one triangle",
            figure: .schematic(DiveInCircuits.opAmpFigure, regions: [
                SchematicRegion("Input stage", parts: ["Q1", "Q2", "Q3", "Q4", "I1"]),
                SchematicRegion("Gain stage", parts: ["Q5", "C1"]),
                SchematicRegion("Output stage", parts: ["D1", "D2", "Q6", "Q7", "I2"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    The op-amp symbol hides a complete transistor circuit. A classic op-amp like the 741 has \
                    about twenty transistors, but they form the three stages of this seven-transistor \
                    version. Point at a stage below to find it in the schematic.
                    """),
                DiveInSection("Input stage", region: 0, """
                    Q1 and Q2 are a [differential pair](divein:differential-pair): they share the current of \
                    I1, and the difference between the inputs decides how it divides. Q3 and Q4 form a \
                    [current mirror](divein:current-mirror) that copies Q1's current to the right-hand side, \
                    so where Q2 and Q4 meet, the stage's output gets the difference of the two currents. \
                    A change common to both inputs moves both currents equally and cancels out.
                    """),
                DiveInSection("Gain stage", region: 1, """
                    Q5 is a common-emitter amplifier whose load is the current source I2, so its voltage \
                    gain is huge: together, the two stages give this op-amp an open-loop gain of nearly 200 000.

                    C1, the **compensation capacitor**, makes the gain fall with frequency so that the \
                    amplifier stays stable with feedback. It sets the gain–bandwidth product, about 3 MHz \
                    here, and the **slew rate**, the fastest the output can move: I1 / C1 = 1 V/µs.
                    """),
                DiveInSection("Output stage", region: 2, """
                    Q6 and Q7 are a [push-pull pair](divein:push-pull) of emitter followers: the output \
                    follows the gain stage, with the current to drive a load. Q6 pushes current out and Q7 \
                    pulls it in. The diodes D1 and D2 hold their bases about 1.2 V apart, so both are \
                    always slightly on.
                    """),
                DiveInSection("Try it", """
                    Open the circuit: it's this op-amp in an inverting amplifier with a gain of −10, like \
                    the example with the ideal op-amp. Switch to an AC sweep to see the bandwidth limit \
                    the ideal model doesn't have.
                    """),
            ],
            deeper: ["differential-pair", "current-mirror", "push-pull", "bjt"],
            circuit: DiveInCircuits.opAmpAmplifier, lesson: "inverting-amplifier")
    }

    // MARK: Building blocks

    static var differentialPair: DiveInTopic {
        let circuit = DiveInCircuits.differentialPair
        return DiveInTopic(
            id: "differential-pair", category: .buildingBlocks, title: "Differential Pair",
            headline: "Two transistors sharing one current",
            figure: .schematic(circuit, regions: []),
            sections: [
                DiveInSection("Steering a current", """
                    Q1 and Q2 share the 1 mA of I1. With equal inputs, each carries half. When one base \
                    rises above the other, its transistor takes more, and since a [BJT](divein:bjt)'s current \
                    grows exponentially with its base–emitter voltage, it doesn't take much:

                    > Ic1 / Ic2 = e^((V1 − V2) / Vt)

                    A difference of 60 mV sends about 90 % of the current to one side.
                    """),
                DiveInSection("Only the difference", """
                    If both inputs move together, the split doesn't change, and neither do the outputs. A \
                    differential pair amplifies the difference between its inputs and ignores what they \
                    have in common, such as noise picked up by both. That's why every op-amp starts with one.
                    """),
                DiveInSection("Try it", """
                    Open the circuit: V1 swings Q1's base by ±100 mV. Plot I(Q1) and I(Q2) to watch them \
                    trade the 1 mA back and forth. The outputs flatten at the peaks, once all of it has \
                    been steered to one side.
                    """),
            ],
            deeper: ["bjt"], circuit: circuit)
    }

    static var currentMirror: DiveInTopic {
        let circuit = DiveInCircuits.currentMirror
        return DiveInTopic(
            id: "current-mirror", category: .buildingBlocks, title: "Current Mirror",
            headline: "One transistor measures a current, another copies it",
            figure: .schematic(circuit, regions: [
                SchematicRegion("Reference", parts: ["R1", "Q1"]),
                SchematicRegion("Copy", parts: ["Q2", "RL"]),
            ]),
            sections: [
                DiveInSection("Measure", region: 0, """
                    Q1's collector is tied to its base, which makes it behave like a diode: it settles at \
                    whatever base–emitter voltage carries the current through R1, about 1 mA.

                    > I ≈ (Vcc − 0.7 V) / R1
                    """),
                DiveInSection("Copy", region: 1, """
                    Q2's base and emitter are connected to Q1's, so it has the same base–emitter voltage. \
                    Identical [transistors](divein:bjt) with the same VBE carry the same current, so Q2 \
                    copies Q1's current into the load RL, whatever RL is, as long as Q2 stays out of saturation.
                    """),
                DiveInSection("Everywhere in chips", """
                    Chips use mirrors for nearly every bias current: transistors on one chip match closely, \
                    and they take less room than resistors. A transistor twice as large carries twice the \
                    current at the same VBE. Try it: double Q2's saturation current to 20 fA and its \
                    current doubles.
                    """),
            ],
            deeper: ["bjt"], circuit: circuit)
    }

    static var pushPull: DiveInTopic {
        let circuit = DiveInCircuits.pushPull
        return DiveInTopic(
            id: "push-pull", category: .buildingBlocks, title: "Push-Pull Output Stage",
            headline: "One transistor pushes, the other pulls",
            figure: .schematic(circuit, regions: []),
            sections: [
                DiveInSection("Two emitter followers", """
                    Q1, an NPN [transistor](divein:bjt), and Q2, a PNP one, are emitter followers: each \
                    emitter follows its base, one VBE away, with the current gain to drive a heavy load. Q1 \
                    pushes current into the load when the output is positive, and Q2 pulls it out when \
                    it's negative. Each rests while the other works, so little power is wasted.
                    """),
                DiveInSection("Crossover distortion", """
                    Near 0 V, neither transistor has the 0.6 V or so it needs to conduct, so the output \
                    stalls in a dead zone. Open the circuit and compare V(out) with V(in): the output is \
                    flattened wherever the sine crosses zero.
                    """),
                DiveInSection("The fix", """
                    Hold the two bases about 1.2 V apart with two [diodes](divein:diode) carrying a small \
                    current, so that both transistors are always slightly on. That is the output stage \
                    inside the [op-amp](divein:op-amp).
                    """),
            ],
            deeper: ["bjt", "diode"], circuit: circuit)
    }
}

// MARK: - Circuits

/// The circuits of the Dive In topics. Their supply rails are joined by the net labels vcc and vee.
enum DiveInCircuits {
    /// A source that doesn't take part in an AC sweep, for supplies and bias currents.
    private static var quiet: SourceWaveform {
        var waveform = SourceWaveform()
        waveform.acMagnitude = 0
        return waveform
    }

    private static func sine(_ amplitude: Double, _ frequency: Double) -> SourceWaveform {
        var waveform = SourceWaveform(shape: .sine)
        waveform.amplitude = amplitude
        waveform.frequency = frequency
        return waveform
    }

    /// ±`volts` supplies stacked at column `x`: vcc at `top`, ground four rows down, and vee four more.
    private static func splitSupply(_ b: inout Bench, volts: Double, x: Int, top: Int) {
        b.vertical(.voltageSource, "V2", volts, top: GridPoint(x, top), waveform: quiet)
        b.vertical(.voltageSource, "V3", volts, top: GridPoint(x, top + 4), waveform: quiet)
        b.label("vcc", at: GridPoint(x, top))
        b.wire(GridPoint(x, top + 4), GridPoint(x - 2, top + 4))
        b.ground(at: GridPoint(x - 2, top + 4))
        b.wire(GridPoint(x, top + 8), GridPoint(x, top + 9))
        b.label("vee", at: GridPoint(x, top + 9))
    }

    /// A seven-transistor op-amp on ±12 V rails at y = 2 and y = 28. The − input is Q1's base at
    /// (16, 14), the + input Q2's base at (26, 14), and the output is wired out to (49, 16).
    private static func opAmp(_ b: inout Bench) {
        // Input stage: the differential pair Q1–Q2, its tail current I1, and the mirror Q3–Q4.
        b.transistor(.bjt, "Q3", .p, at: GridPoint(18, 6))
        b.transistor(.bjt, "Q4", .p, at: GridPoint(28, 6))
        b.transistor(.bjt, "Q1", at: GridPoint(18, 14))
        b.transistor(.bjt, "Q2", at: GridPoint(28, 14))
        b.wire(GridPoint(19, 2), GridPoint(19, 4))
        b.wire(GridPoint(29, 2), GridPoint(29, 4))
        b.wire(GridPoint(19, 8), GridPoint(19, 12))
        b.wire(GridPoint(29, 8), GridPoint(29, 12))
        // Q3 is diode-connected: both mirror bases join its collector.
        b.wire(GridPoint(16, 6), GridPoint(16, 9), GridPoint(19, 9))
        b.wire(GridPoint(26, 6), GridPoint(26, 9), GridPoint(19, 9))
        b.wire(GridPoint(19, 16), GridPoint(19, 18), GridPoint(29, 18), GridPoint(29, 16))
        b.vertical(.currentSource, "I1", 100e-6, top: GridPoint(24, 18), waveform: quiet)
        b.wire(GridPoint(24, 22), GridPoint(24, 28))

        // Gain stage: Q5 drives the output stage; C1 feeds its collector back to its base.
        b.transistor(.bjt, "Q5", .p, at: GridPoint(36, 10))
        b.wire(GridPoint(29, 10), GridPoint(34, 10))
        b.wire(GridPoint(37, 2), GridPoint(37, 8))
        b.vertical(.capacitor, "C1", 100e-12, top: GridPoint(32, 10))
        b.wire(GridPoint(32, 14), GridPoint(37, 14), GridPoint(37, 12))

        // Output stage: I2 draws Q5's current through D1 and D2, which bias the bases of Q6 and Q7.
        b.transistor(.bjt, "Q6", at: GridPoint(45, 12))
        b.transistor(.bjt, "Q7", .p, at: GridPoint(45, 20))
        b.wire(GridPoint(37, 12), GridPoint(43, 12))
        b.vertical(.diode, "D1", ComponentKind.diode.defaultValue, top: GridPoint(41, 12))
        b.vertical(.diode, "D2", ComponentKind.diode.defaultValue, top: GridPoint(41, 16))
        b.wire(GridPoint(41, 20), GridPoint(43, 20))
        b.vertical(.currentSource, "I2", 200e-6, top: GridPoint(41, 20), waveform: quiet)
        b.wire(GridPoint(41, 24), GridPoint(41, 28))
        b.wire(GridPoint(46, 2), GridPoint(46, 10))
        b.wire(GridPoint(46, 22), GridPoint(46, 28))
        b.wire(GridPoint(46, 14), GridPoint(46, 18))
        b.wire(GridPoint(46, 16), GridPoint(49, 16))
        b.label("out", at: GridPoint(49, 16))

        b.wire(GridPoint(19, 2), GridPoint(46, 2))
        b.label("vcc", at: GridPoint(46, 2))
        b.wire(GridPoint(24, 28), GridPoint(46, 28))
        b.label("vee", at: GridPoint(46, 28))
    }

    /// The op-amp alone, with its inputs labeled.
    static var opAmpFigure: Circuit {
        var b = Bench()
        opAmp(&b)
        b.wire(GridPoint(16, 14), GridPoint(12, 14))
        b.label("in−", at: GridPoint(12, 14))
        b.wire(GridPoint(26, 14), GridPoint(24, 14))
        b.label("in+", at: GridPoint(24, 14))
        return b.circuit
    }

    /// The op-amp in an inverting amplifier with a gain of −R2 / R1 = −10, like the example with the ideal op-amp.
    static var opAmpAmplifier: Circuit {
        var b = Bench()
        opAmp(&b)
        b.vertical(.voltageSource, "V1", 0, top: GridPoint(2, 14), waveform: sine(0.5, 1e3))
        b.ground(at: GridPoint(2, 18))
        b.wire(GridPoint(2, 14), GridPoint(8, 14))
        b.label("in", at: GridPoint(5, 14))
        b.horizontal(.resistor, "R1", 1e3, left: GridPoint(8, 14))
        b.wire(GridPoint(12, 14), GridPoint(16, 14))
        // R2 feeds the output back along the bottom, around the end of the supply rails.
        b.wire(GridPoint(12, 14), GridPoint(12, 31), GridPoint(26, 31))
        b.horizontal(.resistor, "R2", 10e3, left: GridPoint(26, 31))
        b.wire(GridPoint(30, 31), GridPoint(49, 31), GridPoint(49, 16))
        b.wire(GridPoint(26, 14), GridPoint(24, 14))
        b.ground(at: GridPoint(24, 14))
        splitSupply(&b, volts: 12, x: 53, top: 4)
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.initialConditions = .operatingPoint
        b.circuit.simulation.stopTime = 3e-3
        return b.circuit
    }

    /// A differential pair with 10 kΩ collector resistors and a 1 mA tail; V1 drives Q1's base and Q2's is grounded.
    static var differentialPair: Circuit {
        var b = Bench()
        b.transistor(.bjt, "Q1", at: GridPoint(14, 12))
        b.transistor(.bjt, "Q2", at: GridPoint(24, 12))
        b.vertical(.resistor, "R1", 10e3, top: GridPoint(15, 2))
        b.vertical(.resistor, "R2", 10e3, top: GridPoint(25, 2))
        b.wire(GridPoint(15, 2), GridPoint(25, 2))
        b.label("vcc", at: GridPoint(25, 2))
        b.wire(GridPoint(15, 6), GridPoint(15, 10))
        b.wire(GridPoint(25, 6), GridPoint(25, 10))
        b.label("out1", at: GridPoint(15, 8))
        b.label("out2", at: GridPoint(25, 8))
        b.wire(GridPoint(15, 14), GridPoint(15, 16), GridPoint(25, 16), GridPoint(25, 14))
        b.vertical(.currentSource, "I1", 1e-3, top: GridPoint(20, 16), waveform: quiet)
        b.wire(GridPoint(20, 20), GridPoint(20, 22))
        b.label("vee", at: GridPoint(20, 22))
        b.wire(GridPoint(22, 12), GridPoint(20, 12))
        b.ground(at: GridPoint(20, 12))
        b.vertical(.voltageSource, "V1", 0, top: GridPoint(6, 12), waveform: sine(0.1, 1e3))
        b.ground(at: GridPoint(6, 16))
        b.wire(GridPoint(6, 12), GridPoint(12, 12))
        b.label("in", at: GridPoint(9, 12))
        splitSupply(&b, volts: 12, x: 30, top: 4)
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 3e-3
        return b.circuit
    }

    /// Q1 measures the current through R1 and Q2 copies it into RL.
    static var currentMirror: Circuit {
        var b = Bench()
        b.vertical(.resistor, "R1", 11e3, top: GridPoint(11, 2))
        b.wire(GridPoint(11, 6), GridPoint(11, 10))
        b.transistor(.bjt, "Q1", at: GridPoint(10, 12))
        b.transistor(.bjt, "Q2", at: GridPoint(20, 12))
        // Q1 is diode-connected: both bases join its collector.
        b.wire(GridPoint(8, 12), GridPoint(8, 8), GridPoint(11, 8))
        b.wire(GridPoint(18, 12), GridPoint(18, 8), GridPoint(11, 8))
        b.vertical(.resistor, "RL", 4.7e3, top: GridPoint(21, 2))
        b.wire(GridPoint(21, 6), GridPoint(21, 10))
        b.label("out", at: GridPoint(21, 8))
        b.wire(GridPoint(11, 14), GridPoint(11, 16))
        b.wire(GridPoint(21, 14), GridPoint(21, 16))
        b.wire(GridPoint(11, 2), GridPoint(26, 2))
        b.vertical(.voltageSource, "V1", 12, top: GridPoint(26, 2))
        b.wire(GridPoint(26, 6), GridPoint(26, 16))
        b.wire(GridPoint(11, 16), GridPoint(26, 16))
        b.ground(at: GridPoint(16, 16))
        b.circuit.simulation.analysis = .operatingPoint
        return b.circuit
    }

    /// A class B output stage: complementary emitter followers with their bases tied to the input.
    static var pushPull: Circuit {
        var b = Bench()
        b.transistor(.bjt, "Q1", at: GridPoint(16, 8))
        b.transistor(.bjt, "Q2", .p, at: GridPoint(16, 14))
        b.wire(GridPoint(17, 6), GridPoint(17, 2))
        b.label("vcc", at: GridPoint(17, 2))
        b.wire(GridPoint(17, 16), GridPoint(17, 20))
        b.label("vee", at: GridPoint(17, 20))
        b.wire(GridPoint(14, 8), GridPoint(12, 8), GridPoint(12, 14), GridPoint(14, 14))
        b.wire(GridPoint(17, 10), GridPoint(17, 12))
        b.wire(GridPoint(17, 11), GridPoint(21, 11))
        b.label("out", at: GridPoint(19, 11))
        b.vertical(.resistor, "RL", 1e3, top: GridPoint(21, 11))
        b.ground(at: GridPoint(21, 15))
        b.vertical(.voltageSource, "V1", 0, top: GridPoint(6, 11), waveform: sine(5, 1e3))
        b.ground(at: GridPoint(6, 15))
        b.wire(GridPoint(6, 11), GridPoint(12, 11))
        b.label("in", at: GridPoint(9, 11))
        splitSupply(&b, volts: 12, x: 28, top: 4)
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 2e-3
        return b.circuit
    }

    /// A 9 V battery modeled as an ideal source with an internal resistance, driving the load RL.
    static var battery: Circuit {
        var b = Bench()
        b.vertical(.voltageSource, "V1", 9, top: GridPoint(6, 6))
        b.wire(GridPoint(6, 6), GridPoint(8, 6))
        b.horizontal(.resistor, "Rint", 2, left: GridPoint(8, 6))
        b.wire(GridPoint(12, 6), GridPoint(20, 6))
        b.label("out", at: GridPoint(16, 6))
        b.vertical(.resistor, "RL", 20, top: GridPoint(20, 6))
        b.wire(GridPoint(6, 10), GridPoint(20, 10))
        b.ground(at: GridPoint(6, 10))
        b.circuit.simulation.analysis = .operatingPoint
        return b.circuit
    }

    /// A BJT current source: the divider R1–R2 fixes the base voltage and RE the current through the load RL.
    static var transistorCurrentSource: Circuit {
        var b = Bench()
        b.vertical(.resistor, "R1", 47e3, top: GridPoint(10, 2))
        b.wire(GridPoint(10, 6), GridPoint(10, 8))
        b.vertical(.resistor, "R2", 10e3, top: GridPoint(10, 8))
        b.wire(GridPoint(10, 12), GridPoint(10, 16))
        b.wire(GridPoint(10, 8), GridPoint(14, 8))
        b.transistor(.bjt, "Q1", at: GridPoint(16, 8))
        b.vertical(.resistor, "RL", 4.7e3, top: GridPoint(17, 2))
        b.vertical(.resistor, "RE", 1.3e3, top: GridPoint(17, 10))
        b.wire(GridPoint(17, 14), GridPoint(17, 16))
        b.wire(GridPoint(10, 2), GridPoint(22, 2))
        b.vertical(.voltageSource, "V1", 12, top: GridPoint(22, 2))
        b.wire(GridPoint(22, 6), GridPoint(22, 16))
        b.wire(GridPoint(10, 16), GridPoint(22, 16))
        b.ground(at: GridPoint(14, 16))
        b.circuit.simulation.analysis = .operatingPoint
        return b.circuit
    }
}
