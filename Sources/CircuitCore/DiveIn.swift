import Foundation

// MARK: - Topics

/// A page of Dive In: what is inside a part, or how one of the building blocks inside a part
/// works. Topics link to deeper ones, from the op-amp down to the pn junction.
public struct DiveInTopic: Identifiable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case parts = "Parts"
        case buildingBlocks = "Building Blocks"
        case logic = "Logic"
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
    /// A CMOS gate's transistors as switches, opened and closed by inputs the reader sets.
    case cmosSwitches
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
        resistor, capacitor, inductor, diode, bjt, mosfet, voltageSource, currentSource, opAmp, comparator, logicGate,
        timer, regulator,
        differentialPair, currentMirror, pushPull, schmittTrigger,
        cmosInverter, cmosNAND, cmosNOR, andOr, xorGate, srLatch,
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
        case .comparator: "comparator"
        case .logicGate: "logic-gate"
        case .timer: "timer"
        case .regulator: "regulator"
        case .ground, .netLabel: nil
        }
        return id.flatMap(topic(withID:))
    }

    /// The topic about what is inside `component`: for a logic gate, its function's transistors.
    public static func topic(for component: Component) -> DiveInTopic? {
        guard component.kind == .logicGate, let function = component.logic?.function else { return topic(for: component.kind) }
        return topic(withID: topicID(for: function))
    }

    /// The topic about the transistors inside a gate with `function`.
    public static func topicID(for function: LogicFunction) -> String {
        switch function {
        case .not: "cmos-inverter"
        case .nand: "cmos-nand"
        case .nor: "cmos-nor"
        case .and, .or: "and-or"
        case .xor, .xnor: "xor-gate"
        }
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

    static var logicGate: DiveInTopic {
        DiveInTopic(
            id: "logic-gate", category: .parts, title: "Logic Gate",
            headline: "Transistor switches that compute",
            figure: .illustration(.cmosSwitches),
            sections: [
                DiveInSection("Ones and zeros", """
                    A logic gate works with just two levels of voltage: near its supply, a **1** (high), and \
                    near ground, a **0** (low). Anything above about 70 % of the supply counts as a 1, and \
                    anything below 30 % as a 0. Each gate drives its output all the way to one level or the \
                    other, so a signal that picked up some noise comes out clean again. That's why digital \
                    signals can pass through billions of gates without degrading, where an analog one would drown.
                    """),
                DiveInSection("Pull-up and pull-down", """
                    Inside a CMOS gate are two networks of [MOSFETs](divein:mosfet) used as switches. \
                    P-channel transistors connect the output to the supply: the **pull-up** network. \
                    N-channel ones connect it to ground: the **pull-down** network. An n-channel transistor \
                    conducts when its gate is high, a p-channel one when its gate is low.

                    The two networks are complementary: for every combination of inputs, exactly one of them \
                    conducts. In a [NAND gate](divein:cmos-nand), the pull-down transistors are in series, so \
                    the output falls only when both inputs are high. Set the inputs above and follow the path \
                    that conducts.
                    """),
                DiveInSection("Every function", """
                    A high input can only switch on an n-channel transistor, which pulls toward ground, so a \
                    single CMOS stage always inverts: NOT, NAND, and NOR are the natural gates. [AND and \
                    OR](divein:and-or) are a NAND or NOR followed by an inverter. And NAND alone is enough to \
                    build any logic function at all: [XOR](divein:xor-gate) takes four of them, and two make \
                    a [latch](divein:sr-latch) that remembers a bit.
                    """),
                DiveInSection("Propagation delay", """
                    A gate's output drives the gates of the next transistors, which are small \
                    [capacitors](divein:capacitor). Its transistors charge and discharge them through their \
                    channels, and that takes time: the **propagation delay**, about 10 ns for a 74HC logic \
                    chip and a few picoseconds inside a processor. Current flows only while the gate switches, \
                    so a CMOS chip's power grows with its clock frequency.
                    """),
                DiveInSection("In MT Circuit", """
                    A logic gate drives its output toward 0 V or its supply, 5 V by default, through 50 Ω. \
                    Its supply is implicit: there are no power pins, and the levels are relative to ground. \
                    Inputs switch at half the supply and draw no current. The output follows its inputs one \
                    propagation delay later, 10 ns by default. To see the transistors inside each gate, dive \
                    deeper below.
                    """),
            ],
            deeper: ["cmos-inverter", "cmos-nand", "cmos-nor", "and-or", "xor-gate", "sr-latch", "mosfet"],
            lesson: "logic-gates")
    }

    static var comparator: DiveInTopic {
        DiveInTopic(
            id: "comparator", category: .parts, title: "Comparator",
            headline: "An op-amp's gain, with nothing to hold it back",
            figure: .schematic(DiveInCircuits.comparatorFigure, regions: [
                SchematicRegion("Input stage", parts: ["Q1", "Q2", "Q3", "Q4", "I1"]),
                SchematicRegion("Gain stage", parts: ["Q5"]),
                SchematicRegion("Output", parts: ["Q6", "RB"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    A comparator tells which of two voltages is higher. Its output is high while V+ is above \
                    V−, and low while it is below: one bit about two analog voltages. Inside, it starts out \
                    like an [op-amp](divein:op-amp). Point at a stage below to find it in the schematic.
                    """),
                DiveInSection("Input stage", region: 0, """
                    Q1 and Q2 are a [differential pair](divein:differential-pair) sharing the 20 µA of I1, with \
                    the [current mirror](divein:current-mirror) Q3–Q4 as their load. A few millivolts between \
                    the inputs unbalance them, and with only transistors for loads, the stage's output, at \
                    Q2's collector, swings from one extreme to the other.
                    """),
                DiveInSection("Gain stage", region: 1, """
                    Q5 amplifies again. An op-amp has a compensation capacitor here, to stay stable with \
                    negative feedback, and that capacitor limits how fast its output can move. A comparator is \
                    never meant to have feedback, so it has none, and its output switches in a fraction of a \
                    microsecond.
                    """),
                DiveInSection("Open-collector output", region: 2, """
                    When V+ falls below V−, the first stage's output falls, Q5 turns on, and Q5 turns on Q6, \
                    which pulls the output to ground. When V+ is higher, Q6 turns off and lets go. Q6 can only \
                    pull down: comparators like the LM393 leave the **pull-up** resistor, RP here, to you. Its \
                    supply sets the output's high level, so a comparator on 12 V can drive 3.3 V logic, and \
                    several outputs can share one pull-up, any of them able to pull it low.
                    """),
                DiveInSection("Try it", """
                    Open the circuit: V(in) is a 1 kHz sine that the comparator compares with 2.5 V, and \
                    V(out) is a square wave. With noise on the input, a comparator chatters at every crossing; \
                    the cure is a [Schmitt trigger](divein:schmitt-trigger).
                    """),
                DiveInSection("In MT Circuit", """
                    A comparator drives its output toward 0 V or its supply, 5 V by default, through 50 Ω, \
                    like a logic gate. Its supply is implicit: there are no power pins. Its output swings over \
                    a few millivolts of input and follows the inputs 100 ns later by default, and its inputs \
                    draw no current.
                    """),
            ],
            deeper: ["differential-pair", "current-mirror", "schmitt-trigger", "bjt"],
            circuit: DiveInCircuits.comparatorTest, lesson: "comparator")
    }

    static var timer: DiveInTopic {
        DiveInTopic(
            id: "timer", category: .parts, title: "555 Timer",
            headline: "Two comparators, a latch, and a switch",
            figure: .schematic(DiveInCircuits.timerFigure, regions: [
                SchematicRegion("Divider", parts: ["R1", "R2", "R3"]),
                SchematicRegion("Comparators", parts: ["U1", "U2"]),
                SchematicRegion("Latch", parts: ["U3", "U4"]),
                SchematicRegion("Output", parts: ["U5"]),
                SchematicRegion("Discharge", parts: ["Q1"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    The 555 came out in 1972, and by some estimates a billion are still made every year. Its \
                    25 transistors form the five blocks of this circuit, built here from parts, with the \
                    555's pins as labels. Point at a block below to find it in the schematic.
                    """),
                DiveInSection("Three resistors", region: 0, """
                    Three equal resistors, 5 kΩ each, divide the supply: ctrl sits at ⅔ of it, and lo at ⅓. \
                    Both thresholds are fractions of the supply, so the 555's timing hardly depends on it: it \
                    keeps time on anything from 4.5 V to 16 V. Driving the CTRL pin moves both thresholds.
                    """),
                DiveInSection("Two comparators", region: 1, """
                    [Comparator](divein:comparator) U1 raises r while the threshold pin, thr, is above ⅔ of \
                    the supply. U2 raises s while the trigger pin, trig, is below ⅓.
                    """),
                DiveInSection("A latch", region: 2, """
                    U3 and U4 are an [SR latch](divein:sr-latch): s sets it, r resets it, and between their \
                    pulses it remembers. With the two thresholds, that makes the 555 a \
                    [Schmitt trigger](divein:schmitt-trigger) with very wide hysteresis: once thr has risen past \
                    ⅔, nothing changes until trig falls below ⅓. If both act at once, the trigger wins: s \
                    forces qbar low, and qbar is what drives the output.
                    """),
                DiveInSection("Output", region: 3, """
                    U5 inverts qbar into out, which is high while the latch is set. A real 555's output stage \
                    is a [push-pull pair](divein:push-pull) that can source or sink 200 mA, enough for a relay \
                    or a small speaker.
                    """),
                DiveInSection("Discharge", region: 4, """
                    While the latch is reset, qbar turns on Q1 through R4. Q1 is a [BJT](divein:bjt) that \
                    connects dis to ground, and that's what empties the timing capacitor in every 555 circuit.
                    """),
                DiveInSection("Try it", """
                    Open the circuit: it's this 555 in the astable circuit of the tutorial, with RA = 1 kΩ, \
                    RB = 6.8 kΩ, and C1 = 100 nF, oscillating near 1 kHz. Plot V(thr), V(s), and V(r) to watch \
                    the comparators fire at 1.67 V and 3.33 V. Its gates and comparators have an implicit \
                    5 V supply, so it only works on 5 V.
                    """),
                DiveInSection("In MT Circuit", """
                    The 555 timer part works like this circuit, with an output that swings from rail to rail \
                    through 10 Ω, as a CMOS 555's does; a bipolar NE555's high output is about 1.7 V below VCC. \
                    Its discharge pin connects to GND through 10 Ω, its RESET pin resets it below 0.7 V, and \
                    its output follows its latch 100 ns later, or one time step later if the step is longer.
                    """),
            ],
            deeper: ["comparator", "sr-latch", "schmitt-trigger", "push-pull", "bjt"],
            circuit: DiveInCircuits.timerAstable, lesson: "555-timer")
    }

    static var regulator: DiveInTopic {
        DiveInTopic(
            id: "regulator", category: .parts, title: "Voltage Regulator",
            headline: "An amplifier that holds its own output steady",
            figure: .schematic(DiveInCircuits.regulatorFigure, regions: [
                SchematicRegion("Reference", parts: ["V2"]),
                SchematicRegion("Error amplifier", parts: ["U1"]),
                SchematicRegion("Pass transistor", parts: ["Q1"]),
                SchematicRegion("Divider", parts: ["R1", "R2"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    A linear regulator is a feedback loop: it measures its output, compares it with a \
                    reference, and adjusts a transistor until they agree. An LM317's few dozen transistors form \
                    the three blocks of this circuit, which sets its output with R1 and R2, as in the tutorial. \
                    Point at a block below to find it in the schematic.
                    """),
                DiveInSection("Reference", region: 0, """
                    V2 stands for a **bandgap reference**: a few transistors whose voltage hardly changes with \
                    temperature or supply. A [pn junction](divein:diode)'s voltage falls by about 2 mV for each \
                    degree warmer, while the difference between two junctions carrying different currents \
                    rises. Added in the right proportion they cancel, at about 1.25 V, near the bandgap of \
                    silicon. The reference sits on adj, so the regulator holds out 1.25 V above it.
                    """),
                DiveInSection("Error amplifier", region: 1, """
                    U1, an [op-amp](divein:op-amp), compares out with adj plus the reference, and drives the \
                    pass transistor until they are equal: the same negative feedback as in an amplifier.
                    """),
                DiveInSection("Pass transistor", region: 2, """
                    Q1, a [BJT](divein:bjt) emitter follower, carries the load current from in to out. It drops \
                    whatever voltage the input has to spare and turns it into heat, (Vin − Vout) · I. That's \
                    why regulators have heat sinks, and why most electronics now run from switching \
                    regulators, which waste far less.
                    """),
                DiveInSection("Divider", region: 3, """
                    R1 and R2 divide the output, so that the 1.25 V across R1 sets it:

                    > Vout = 1.25 V · (1 + R2 / R1) = 3.3 V
                    """),
                DiveInSection("Dropout", """
                    The pass transistor needs headroom: its base sits 0.7 V above out, and the circuits that \
                    drive it need more. An LM317's input must stay about 2 V above its output, or the input's \
                    ripple passes through. **Low-dropout** regulators (LDOs) use a PNP or p-channel pass \
                    transistor, which can bring the output within a few tenths of a volt of the input.

                    Open the circuit: the input ripples between 8 V and 10 V, and V(out) holds at 3.3 V. Its \
                    ideal op-amp can drive Q1's base as far above the input as it likes, so unlike a real \
                    LM317, it keeps regulating with only a tenth of a volt to spare.
                    """),
                DiveInSection("In MT Circuit", """
                    The voltage regulator part holds its output V_ref above its ADJ pin, 1.25 V by default, \
                    through 10 mΩ, as long as its input is at least the dropout voltage, 2 V by default, above \
                    the output. 50 µA flows out of ADJ, and the pass transistor can't carry current backward. \
                    For a fixed regulator like the 7805, ground ADJ and set V_ref to 5 V.
                    """),
            ],
            deeper: ["op-amp", "bjt", "diode"], circuit: DiveInCircuits.regulatorTest, lesson: "voltage-regulator")
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

    static var schmittTrigger: DiveInTopic {
        let circuit = Bench.schmittTrigger(feedback: 100e3)
        return DiveInTopic(
            id: "schmitt-trigger", category: .buildingBlocks, title: "Schmitt Trigger",
            headline: "Two thresholds, so that noise can't flip the output back",
            figure: .schematic(circuit, regions: [SchematicRegion("Positive feedback", parts: ["R1", "R2"])]),
            sections: [
                DiveInSection("Chatter", """
                    A [comparator](divein:comparator) with one threshold switches every time its input crosses \
                    it. A slow, noisy input crosses it several times in a row, and the output chatters: the \
                    circuits after it see a burst of edges where there should be one.
                    """),
                DiveInSection("Positive feedback", region: 0, """
                    R2 feeds some of the output back to the + input. Negative feedback, as in an amplifier, \
                    pulls a circuit toward balance; positive feedback pushes it away. Once the output switches \
                    high, it raises V+, which holds it high, and the input must fall past a lower threshold to \
                    switch it back. Then the output lowers V+ and holds itself low. Between the thresholds, the \
                    output remembers which one the input crossed last, like a [latch](divein:sr-latch). Here \
                    they are 5 V · R1 / R2 = 0.5 V apart:

                    > V_up = 2.75 V,   V_down = 2.25 V
                    """),
                DiveInSection("Everywhere", """
                    Schmitt triggers clean up signals from buttons, sensors, and long cables, and many logic \
                    chips, like the 74HC14, build them into their inputs. The [555 timer](divein:timer) is one \
                    with very wide hysteresis: its thresholds are ⅓ and ⅔ of its supply.

                    Open the circuit: the input is a 1 kHz sine with 20 kHz noise on it. Delete R2 to see the \
                    output chatter at each crossing.
                    """),
            ],
            deeper: ["comparator"], circuit: circuit, lesson: "comparator")
    }

    // MARK: Logic

    static var cmosInverter: DiveInTopic {
        let circuit = Examples.cmosInverter.circuit
        return DiveInTopic(
            id: "cmos-inverter", category: .logic, title: "CMOS Inverter",
            headline: "Inside a NOT gate: one transistor pulls up, the other pulls down",
            figure: .schematic(circuit, regions: [
                SchematicRegion("Pull-up", parts: ["M2"]),
                SchematicRegion("Pull-down", parts: ["M1"]),
            ]),
            sections: [
                DiveInSection("Complementary switches", """
                    A NOT gate is two [MOSFETs](divein:mosfet) with their gates joined: M2, a p-channel \
                    transistor, from the supply to the output, and M1, an n-channel one, from the output to \
                    ground. "Complementary" is the C in CMOS.
                    """),
                DiveInSection("Pull-up", region: 0, """
                    A low input puts M2's gate 5 V below its source, far past its threshold, so M2 conducts \
                    and connects the output to the supply, while M1 is off. The output is high.
                    """),
                DiveInSection("Pull-down", region: 1, """
                    A high input turns M1 on and M2 off: the output connects to ground and is low. In either \
                    state one transistor is off, so no current flows from the supply to ground. A CMOS gate \
                    at rest uses almost no power.
                    """),
                DiveInSection("Gain in the middle", """
                    Only near half the supply are both transistors partly on. There, a small change at the \
                    input swings the output a long way: the inverter is an amplifier with a high gain. That \
                    gain is what snaps a sloppy input back to clean levels.

                    Open the circuit: the input ramps slowly up and down, and the output switches abruptly as \
                    the input passes 2.5 V. Plot I(V2) to see current flow from the supply only while it switches.
                    """),
            ],
            deeper: ["mosfet"], circuit: circuit, lesson: "cmos-gates")
    }

    static var cmosNAND: DiveInTopic {
        let circuit = DiveInCircuits.cmosGate(.nand)
        return DiveInTopic(
            id: "cmos-nand", category: .logic, title: "NAND Gate",
            headline: "Two switches in series below, two in parallel above",
            figure: .schematic(DiveInCircuits.cmosGate(.nand, sources: false), regions: [
                SchematicRegion("Pull-up", parts: ["M2", "M4"]),
                SchematicRegion("Pull-down", parts: ["M1", "M3"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    A NAND gate's output is 0 only when both of its inputs are 1:

                    > Y = NOT (A AND B)

                    It takes four [MOSFETs](divein:mosfet), two more than an [inverter](divein:cmos-inverter).
                    """),
                DiveInSection("Pull-down in series", region: 1, """
                    M1 and M3, the n-channel transistors, are in series between the output and ground. \
                    Current can only get through if both are on, so the output is pulled low only when A and \
                    B are both high.
                    """),
                DiveInSection("Pull-up in parallel", region: 0, """
                    M2 and M4, the p-channel transistors, are in parallel between the supply and the output. \
                    Either one connects it, so the output is high as soon as A or B is low: exactly when the \
                    pull-down is open.
                    """),
                DiveInSection("Try it", """
                    Open the circuit: A and B count through all four combinations, 00, 01, 10, and 11, a \
                    millisecond each, and V(y) falls only during the last. NAND is the workhorse of \
                    logic: any function can be built from NAND gates alone.
                    """),
            ],
            deeper: ["cmos-inverter", "mosfet"], circuit: circuit, lesson: "cmos-gates")
    }

    static var cmosNOR: DiveInTopic {
        let circuit = DiveInCircuits.cmosGate(.nor)
        return DiveInTopic(
            id: "cmos-nor", category: .logic, title: "NOR Gate",
            headline: "Two switches in parallel below, two in series above",
            figure: .schematic(DiveInCircuits.cmosGate(.nor, sources: false), regions: [
                SchematicRegion("Pull-up", parts: ["M2", "M4"]),
                SchematicRegion("Pull-down", parts: ["M1", "M3"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    A NOR gate's output is 1 only when both of its inputs are 0:

                    > Y = NOT (A OR B)

                    It is the mirror image of the [NAND gate](divein:cmos-nand): its networks swap series \
                    for parallel.
                    """),
                DiveInSection("Pull-down in parallel", region: 1, """
                    Either input high turns on M1 or M3, and either one pulls the output to ground.
                    """),
                DiveInSection("Pull-up in series", region: 0, """
                    The output connects to the supply only through both M2 and M4, so only when A and B \
                    are both low.
                    """),
                DiveInSection("Why designers prefer NAND", """
                    In silicon, holes move two to three times slower than electrons, so a p-channel \
                    transistor conducts less than an n-channel one of the same size. A NOR gate puts its \
                    slow p-channel transistors in series, which makes it slower still, unless they are made \
                    larger. NAND gates put the fast n-channel ones in series instead, so chips are built \
                    mostly from NANDs.
                    """),
            ],
            deeper: ["cmos-inverter", "mosfet"], circuit: circuit, lesson: "sr-latch")
    }

    static var andOr: DiveInTopic {
        let circuit = DiveInCircuits.cmosAND
        return DiveInTopic(
            id: "and-or", category: .logic, title: "AND and OR Gates",
            headline: "A NAND or a NOR, then an inverter",
            figure: .schematic(DiveInCircuits.cmosAND(sources: false), regions: [
                SchematicRegion("NAND", parts: ["M1", "M2", "M3", "M4"]),
                SchematicRegion("Inverter", parts: ["M5", "M6"]),
            ]),
            sections: [
                DiveInSection("Why not one stage?", """
                    An AND gate's output should rise when its inputs rise. But a rising input can only \
                    switch on an n-channel transistor, and n-channel transistors belong in the pull-down \
                    network: they pull the output toward ground. Every single CMOS stage inverts.
                    """),
                DiveInSection("NAND, then NOT", region: 0, """
                    So an AND gate is a [NAND gate](divein:cmos-nand) whose output feeds an \
                    [inverter](divein:cmos-inverter), six transistors in all. An OR gate is a \
                    [NOR gate](divein:cmos-nor) and an inverter in the same way.
                    """),
                DiveInSection("The cost", region: 1, """
                    The inverter adds two transistors and a second propagation delay. Designers often keep \
                    the logic inverted instead: a NAND followed by a NAND computes the same as an AND \
                    followed by an OR, with fewer transistors.

                    Open the circuit: V(n) is the NAND's output and V(y) the AND's.
                    """),
            ],
            deeper: ["cmos-nand", "cmos-nor", "cmos-inverter"], circuit: circuit, lesson: "logic-gates")
    }

    static var xorGate: DiveInTopic {
        let circuit = DiveInCircuits.xorFromNAND
        return DiveInTopic(
            id: "xor-gate", category: .logic, title: "XOR Gate",
            headline: "Four NAND gates that tell whether two bits differ",
            figure: .schematic(circuit, regions: [
                SchematicRegion("Shared NAND", parts: ["U1"]),
            ]),
            sections: [
                DiveInSection(nil, """
                    XOR, "exclusive or", is 1 when its inputs differ: one or the other, but not both. XNOR \
                    is its inverse, 1 when they are equal.
                    """),
                DiveInSection("Built from NANDs", region: 0, """
                    U1 computes n = NAND(A, B), which is 0 only when both inputs are 1. U2 = NAND(A, n) \
                    is then 0 only when A is 1 and B is 0, and U3 = NAND(n, B) only when B is 1 and A is 0. \
                    U4, a NAND of those two, is 1 when either of them is 0: exactly when the inputs differ.

                    > Y = A XOR B = NAND(NAND(A, n), NAND(n, B))

                    Built from [NAND gates](divein:cmos-nand), that's sixteen transistors; a chip designer's \
                    XOR cell manages with about a dozen.
                    """),
                DiveInSection("Adding and comparing", """
                    XOR adds two bits, leaving out the carry: 0 + 1 = 1, but 1 + 1 = 0, carry 1. Every adder \
                    in a processor is built around XOR gates, and so are circuits that compare numbers bit by \
                    bit, compute parity, and encrypt data.

                    Open the circuit: A and B count through 00, 01, 10, and 11, and V(y) is high in the middle two.
                    """),
            ],
            deeper: ["cmos-nand"], circuit: circuit, lesson: "nand-universal")
    }

    static var srLatch: DiveInTopic {
        let circuit = Examples.srLatch.circuit
        return DiveInTopic(
            id: "sr-latch", category: .logic, title: "SR Latch",
            headline: "Two gates that remember one bit",
            figure: .schematic(circuit, regions: [
                SchematicRegion("Feedback", parts: ["U1", "U2"]),
            ]),
            sections: [
                DiveInSection("Feedback", region: 0, """
                    Each [NOR gate](divein:cmos-nor)'s output feeds one input of the other. With both S and R \
                    at 0, each gate simply inverts the other's output, and that loop has two stable states: \
                    q = 1 with qbar = 0, or q = 0 with qbar = 1. Whichever it is in, it stays. The latch \
                    holds one bit.
                    """),
                DiveInSection("Set and reset", """
                    Raising S forces qbar to 0, and then q to 1: the latch is **set**. Raising R forces q to 0: \
                    it is **reset**. When the input falls again, the feedback keeps the new state.

                    Raising both at once is forbidden: both outputs fall to 0, and if both inputs then fall \
                    together, the latch is left to race toward one state or the other.
                    """),
                DiveInSection("From latches to memory", """
                    A computer's fastest memory, the SRAM in its caches, stores each bit in two \
                    [inverters](divein:cmos-inverter) feeding each other, the same loop with six transistors. \
                    Two latches in a row make a flip-flop, which changes state only on a clock edge: the \
                    registers of every processor are built from them.

                    Open the circuit: R resets the latch at the start, S sets it at 1 ms, and R resets it \
                    again at 3 ms. Between the pulses, V(q) holds.
                    """),
            ],
            deeper: ["cmos-nor"], circuit: circuit, lesson: "sr-latch")
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

    /// A transistor-level NAND or NOR gate (see `Bench.cmosNAND` and `Bench.cmosNOR`). With
    /// `sources`, a 5 V supply, and inputs A and B that count through every combination in 4 ms.
    static func cmosGate(_ function: LogicFunction, sources: Bool = true) -> Circuit {
        var b = Bench()
        if function == .nand { b.cmosNAND() } else { b.cmosNOR() }
        guard sources else { return b.circuit }
        b.supply(at: GridPoint(42, 2), from: function == .nand ? GridPoint(33, 2) : GridPoint(19, 2))
        b.logicInput("VA", "a", top: GridPoint(2, 8), bit: 0, of: 2)
        b.logicInput("VB", "b", top: GridPoint(2, 16), bit: 1, of: 2)
        b.countThrough(inputs: 2)
        return b.circuit
    }

    /// A transistor-level AND gate: the NAND of `Bench.cmosNAND`, with output n, and an inverter
    /// (M6 above M5) from n to y.
    static func cmosAND(sources: Bool) -> Circuit {
        var b = Bench()
        b.cmosNAND(output: "n", outputEnd: 44)
        b.transistor(.mosfet, "M6", .p, at: GridPoint(46, 6))
        b.transistor(.mosfet, "M5", at: GridPoint(46, 14))
        b.wire(GridPoint(33, 2), GridPoint(47, 2), GridPoint(47, 4))
        b.wire(GridPoint(44, 6), GridPoint(44, 14))
        b.wire(GridPoint(47, 8), GridPoint(47, 12))
        b.wire(GridPoint(47, 10), GridPoint(51, 10))
        b.label("y", at: GridPoint(50, 10))
        b.wire(GridPoint(47, 16), GridPoint(47, 18))
        b.ground(at: GridPoint(47, 18))
        guard sources else { return b.circuit }
        b.supply(at: GridPoint(56, 2), from: GridPoint(47, 2))
        b.logicInput("VA", "a", top: GridPoint(2, 8), bit: 0, of: 2)
        b.logicInput("VB", "b", top: GridPoint(2, 16), bit: 1, of: 2)
        b.countThrough(inputs: 2)
        return b.circuit
    }

    static var cmosAND: Circuit { cmosAND(sources: true) }

    /// XOR from four NAND gates: n = NAND(a, b), then y = NAND(NAND(a, n), NAND(n, b)).
    static var xorFromNAND: Circuit {
        var b = Bench()
        b.xorFromNAND()
        b.countThrough(inputs: 2)
        return b.circuit
    }

    // MARK: Chips

    /// A 555 timer built from parts, with its pins as the labels vcc, ctrl, thr, trig, dis, and out.
    /// The divider R1–R3 holds ctrl at ⅔ of vcc and the net lo at ⅓. Comparator U1 raises r while
    /// thr is above ctrl, and U2 raises s while trig is below lo. The NOR latch U3–U4 holds q, and
    /// its qbar drives the output through the inverter U5 and the discharge transistor Q1 through R4.
    /// The gates and comparators have an implicit 5 V supply.
    private static func timerParts(_ b: inout Bench) {
        b.wire(GridPoint(10, 2), GridPoint(13, 2))
        b.label("vcc", at: GridPoint(13, 2))
        b.vertical(.resistor, "R1", 5e3, top: GridPoint(10, 2))
        b.vertical(.resistor, "R2", 5e3, top: GridPoint(10, 6))
        b.wire(GridPoint(10, 10), GridPoint(10, 14))
        b.vertical(.resistor, "R3", 5e3, top: GridPoint(10, 14))
        b.ground(at: GridPoint(10, 18))
        b.wire(GridPoint(10, 6), GridPoint(16, 6))
        b.label("ctrl", at: GridPoint(13, 6))
        b.wire(GridPoint(10, 14), GridPoint(16, 14))
        b.label("lo", at: GridPoint(13, 14))

        // U1: + is thr, − is ctrl. U2: + is lo, − is trig.
        b.comparator("U1", plus: GridPoint(16, 8))
        b.wire(GridPoint(16, 8), GridPoint(13, 8))
        b.label("thr", at: GridPoint(13, 8))
        b.comparator("U2", plus: GridPoint(16, 14))
        b.wire(GridPoint(16, 12), GridPoint(13, 12))
        b.label("trig", at: GridPoint(13, 12))

        // The latch: U3 = NOR(r, qbar) drives q, U4 = NOR(s, q) drives qbar.
        b.gate(.nor, "U3", at: GridPoint(26, 8))
        b.gate(.nor, "U4", at: GridPoint(26, 14))
        b.wire(GridPoint(20, 7), GridPoint(24, 7))
        b.label("r", at: GridPoint(21, 7))
        b.wire(GridPoint(20, 13), GridPoint(24, 13))
        b.label("s", at: GridPoint(21, 13))
        b.wire(GridPoint(24, 9), GridPoint(21, 9))
        b.label("qbar", at: GridPoint(21, 9))
        b.wire(GridPoint(24, 15), GridPoint(21, 15))
        b.label("q", at: GridPoint(21, 15))
        b.wire(GridPoint(28, 8), GridPoint(31, 8))
        b.label("q", at: GridPoint(31, 8))

        // Output and discharge, both driven by qbar.
        b.wire(GridPoint(28, 14), GridPoint(32, 14))
        b.label("qbar", at: GridPoint(29, 14))
        b.gate(.not, "U5", at: GridPoint(34, 14))
        b.wire(GridPoint(36, 14), GridPoint(40, 14))
        b.label("out", at: GridPoint(39, 14))
        b.wire(GridPoint(30, 14), GridPoint(30, 20))
        b.horizontal(.resistor, "R4", 10e3, left: GridPoint(30, 20))
        b.transistor(.bjt, "Q1", at: GridPoint(36, 20))
        b.wire(GridPoint(37, 18), GridPoint(40, 18))
        b.label("dis", at: GridPoint(40, 18))
        b.wire(GridPoint(37, 22), GridPoint(37, 24))
        b.ground(at: GridPoint(37, 24))
    }

    /// The 555 of parts alone.
    static var timerFigure: Circuit {
        var b = Bench()
        timerParts(&b)
        return b.circuit
    }

    /// The 555 of parts in the astable circuit of the tutorial: RA from vcc to dis, RB from dis to
    /// thr and trig, and C1 from there to ground, on a 5 V supply.
    static var timerAstable: Circuit {
        var b = Bench()
        timerParts(&b)
        b.vertical(.voltageSource, "V1", 5, top: GridPoint(2, 2), waveform: quiet)
        b.label("vcc", at: GridPoint(2, 2))
        b.ground(at: GridPoint(2, 6))
        b.wire(GridPoint(40, 18), GridPoint(46, 18))
        b.label("vcc", at: GridPoint(46, 14))
        b.vertical(.resistor, "RA", 1e3, top: GridPoint(46, 14))
        b.vertical(.resistor, "RB", 6.8e3, top: GridPoint(46, 18))
        b.vertical(.capacitor, "C1", 100e-9, top: GridPoint(46, 22))
        b.ground(at: GridPoint(46, 26))
        b.wire(GridPoint(46, 22), GridPoint(52, 22))
        b.label("thr", at: GridPoint(49, 22))
        b.label("trig", at: GridPoint(52, 22))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 6e-3
        return b.circuit
    }

    /// A comparator built from transistors, on a 5 V supply at vcc: the differential pair Q1–Q2
    /// with its tail current I1 and the mirror Q3–Q4, the gain stage Q5, and the open-collector
    /// output Q6 with its pull-up RP. The + input is Q1's base at (16, 14), the − input Q2's at (26, 14).
    private static func comparatorTransistors(_ b: inout Bench) {
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
        b.vertical(.currentSource, "I1", 20e-6, top: GridPoint(24, 18), waveform: quiet)
        b.wire(GridPoint(24, 22), GridPoint(24, 24))

        // Q5 turns on when the first stage's output, at Q2's collector, falls; it then drives Q6 on.
        b.transistor(.bjt, "Q5", .p, at: GridPoint(36, 10))
        b.wire(GridPoint(29, 10), GridPoint(34, 10))
        b.wire(GridPoint(37, 2), GridPoint(37, 8))
        b.wire(GridPoint(37, 12), GridPoint(37, 16), GridPoint(40, 16))
        b.vertical(.resistor, "RB", 10e3, top: GridPoint(38, 16))
        b.wire(GridPoint(38, 20), GridPoint(38, 24))
        b.transistor(.bjt, "Q6", at: GridPoint(42, 16))
        b.wire(GridPoint(43, 18), GridPoint(43, 24))
        b.vertical(.resistor, "RP", 10e3, top: GridPoint(43, 2))
        b.wire(GridPoint(43, 6), GridPoint(43, 14))
        b.wire(GridPoint(43, 10), GridPoint(47, 10))
        b.label("out", at: GridPoint(46, 10))

        b.wire(GridPoint(19, 2), GridPoint(43, 2))
        b.label("vcc", at: GridPoint(33, 2))
        b.wire(GridPoint(24, 24), GridPoint(43, 24))
        b.ground(at: GridPoint(33, 24))
    }

    /// The transistor comparator alone, with its inputs labeled.
    static var comparatorFigure: Circuit {
        var b = Bench()
        comparatorTransistors(&b)
        b.wire(GridPoint(16, 14), GridPoint(12, 14))
        b.label("in+", at: GridPoint(12, 14))
        b.wire(GridPoint(26, 14), GridPoint(24, 14))
        b.label("in−", at: GridPoint(24, 14))
        return b.circuit
    }

    /// The transistor comparator comparing a slow 1 kHz sine, the net in, with the 2.5 V reference V3.
    static var comparatorTest: Circuit {
        var b = Bench()
        comparatorTransistors(&b)
        b.vertical(.voltageSource, "V1", 2.5, top: GridPoint(4, 14), waveform: sine(2, 1e3))
        b.ground(at: GridPoint(4, 18))
        b.wire(GridPoint(4, 14), GridPoint(16, 14))
        b.label("in", at: GridPoint(8, 14))
        b.wire(GridPoint(26, 14), GridPoint(24, 14), GridPoint(24, 12))
        b.label("ref", at: GridPoint(24, 12))
        b.vertical(.voltageSource, "V3", 2.5, top: GridPoint(8, 22), waveform: quiet)
        b.label("ref", at: GridPoint(8, 22))
        b.ground(at: GridPoint(8, 26))
        b.vertical(.voltageSource, "V2", 5, top: GridPoint(50, 2), waveform: quiet)
        b.label("vcc", at: GridPoint(50, 2))
        b.ground(at: GridPoint(50, 6))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 3e-3
        return b.circuit
    }

    /// A linear regulator like the LM317, built from parts: the 1.25 V reference V2 above the net
    /// adj, the error amplifier U1, and the pass transistor Q1 from in to out. R1 from out to adj and
    /// R2 from adj to ground set V(out) = 1.25 V · (1 + R2 / R1) = 3.3 V.
    private static func regulatorParts(_ b: inout Bench) {
        b.wire(GridPoint(6, 4), GridPoint(20, 4))
        b.label("in", at: GridPoint(6, 4))
        b.transistor(.bjt, "Q1", at: GridPoint(19, 8))
        b.wire(GridPoint(20, 4), GridPoint(20, 6))
        b.wire(GridPoint(20, 10), GridPoint(30, 10))
        b.label("out", at: GridPoint(28, 10))
        b.vertical(.resistor, "R1", 240, top: GridPoint(24, 10))
        b.vertical(.resistor, "R2", 394, top: GridPoint(24, 14))
        b.ground(at: GridPoint(24, 18))
        b.wire(GridPoint(24, 14), GridPoint(22, 14))
        b.label("adj", at: GridPoint(22, 14))

        b.opAmp("U1", plus: GridPoint(11, 9))
        b.wire(GridPoint(15, 8), GridPoint(17, 8))
        b.wire(GridPoint(11, 7), GridPoint(9, 7))
        b.label("out", at: GridPoint(9, 7))
        b.wire(GridPoint(11, 9), GridPoint(6, 9))
        b.vertical(.voltageSource, "V2", 1.25, top: GridPoint(6, 9), waveform: quiet)
        b.wire(GridPoint(6, 13), GridPoint(6, 15))
        b.label("adj", at: GridPoint(6, 15))
    }

    /// The regulator of parts alone.
    static var regulatorFigure: Circuit {
        var b = Bench()
        regulatorParts(&b)
        return b.circuit
    }

    /// The regulator of parts fed from V1, 9 V with a ripple of ± 1 V at 100 Hz, driving 100 Ω.
    static var regulatorTest: Circuit {
        var b = Bench()
        regulatorParts(&b)
        var ripple = sine(1, 100)
        ripple.acMagnitude = 1
        b.vertical(.voltageSource, "V1", 9, top: GridPoint(-4, 4), waveform: ripple)
        b.wire(GridPoint(-4, 4), GridPoint(6, 4))
        b.ground(at: GridPoint(-4, 8))
        b.wire(GridPoint(30, 10), GridPoint(34, 10))
        b.vertical(.resistor, "RL", 100, top: GridPoint(34, 10))
        b.ground(at: GridPoint(34, 14))
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 30e-3
        return b.circuit
    }
}
