import Foundation

/// The built-in tutorial: lessons on the fundamentals of electronics, in order. Each explains a
/// concept and sets a challenge on a starting circuit; the app checks the challenge's goals by
/// simulating the learner's circuit.
public enum Tutorial {
    public static let lessons: [Lesson] = [
        firstCircuit,
        ohmsLaw, power, seriesResistors, parallelResistors, combiningResistors, voltageDivider, currentLaw,
        rcTimeConstant, inductors, lowPassFilter, highPassFilter, resonance,
        diode, rectifier, transistorSwitch, transistorBias, mosfet,
        invertingAmplifier, nonInvertingAmplifier,
        logicGates, nandUniversal, binaryAddition, srLatch, propagationDelay, cmosGates,
    ]

    public static func lesson(withID id: String) -> Lesson? {
        lessons.first { $0.id == id }
    }

    /// The lessons grouped by chapter, in order.
    public static var chapters: [(title: String, lessons: [Lesson])] {
        var chapters: [(title: String, lessons: [Lesson])] = []
        for lesson in lessons {
            if chapters.last?.title == lesson.chapter {
                chapters[chapters.count - 1].lessons.append(lesson)
            } else {
                chapters.append((lesson.chapter, [lesson]))
            }
        }
        return chapters
    }

    // MARK: - Getting Started

    static var firstCircuit: Lesson {
        Lesson(
            id: "first-circuit", chapter: "Getting Started", title: "Your First Circuit",
            introduction: """
                A circuit is a closed loop that current flows around. A **voltage source**, like a battery, \
                pushes current out of its **+** terminal, through the other parts, and back into its **−** terminal.

                Every circuit here also needs a **ground** symbol. Ground is the reference point that all \
                voltages are measured from: 0 V by definition.

                To build, press **V** and click to place a voltage source, **R** for a resistor, and **G** for \
                ground. Then press **W** and click from pin to pin to draw wires. A small red square marks a pin \
                that isn't connected yet. Press **Esc** to return to the select tool; select a part to see and \
                change its values in the inspector on the right.
                """,
            challenge: "Build a loop of a voltage source and a resistor, with a ground. The default values, 5 V and 1 kΩ, are fine.",
            goals: [
                .places(.voltageSource, "Place a voltage source"),
                .places(.resistor, "Place a resistor"),
                .places(.ground, "Place a ground symbol"),
                .current("R1", .near(5e-3, tolerance: 0.01)),
            ],
            hints: [
                "Place the voltage source with its + terminal on top (the default), and the resistor to its right.",
                "Draw one wire from the top of the source to one end of the resistor, and another from the other end of the resistor back to the bottom of the source.",
                "Place the ground symbol so that its pin touches the bottom wire or the source's bottom pin.",
            ],
            answer: """
                Current flows out of the source's + terminal, through R1, and back into its − terminal. \
                Its size follows from Ohm's law, the subject of the next lesson: I = V / R = 5 V / 1 kΩ = 5 mA.

                The DC Op analysis below the schematic lists every voltage and current, and writes each net's \
                voltage on the schematic.
                """,
            starter: {
                var circuit = Circuit()
                circuit.simulation.analysis = .operatingPoint
                return circuit
            }(),
            solution: Bench.loop(volts: 5, ohms: 1e3))
    }

    // MARK: - DC Circuits

    static var ohmsLaw: Lesson {
        Lesson(
            id: "ohms-law", chapter: "DC Circuits", title: "Ohm's Law",
            introduction: """
                Three quantities describe what happens in a circuit. **Voltage** V, in volts, is the push \
                between two points. **Current** I, in amperes, is the flow of charge. **Resistance** R, in \
                ohms (Ω), is how strongly a part opposes that flow.

                **Ohm's law** connects them:

                > V = I · R

                so I = V / R and R = V / I. Double the voltage across a resistor and its current doubles; \
                double the resistance and the current halves.

                Values take SI prefixes: type **4.7k** for 4.7 kΩ, **2m** for 2 m (milli), **10u** for 10 µ \
                (micro), and **1meg** for 1 MΩ.
                """,
            challenge: "The 9 V source drives 9 mA through R1. Change R1 so that the current is 2 mA.",
            goals: [
                .current("R1", .near(2e-3, tolerance: 0.01)),
                .keeps("V1", at: 9, unit: "V"),
            ],
            hints: [
                "Select R1 and type a new resistance in the inspector, then press Return.",
                "Rearrange Ohm's law for the resistance: R = V / I.",
            ],
            answer: "R = V / I = 9 V / 2 mA = 4.5 kΩ. Type **4.5k**.",
            starter: Bench.loop(volts: 9, ohms: 1e3),
            solution: Bench.loop(volts: 9, ohms: 4.5e3))
    }

    static var power: Lesson {
        Lesson(
            id: "power", chapter: "DC Circuits", title: "Power",
            introduction: """
                Current flowing through a resistance turns electrical energy into heat. The rate is the \
                **power** P, in watts (W):

                > P = V · I = I² · R = V² / R

                Real resistors are rated for a maximum power; common ones handle ¼ W (250 mW). Beyond that \
                they overheat and fail.

                The DC Op results list the power in every part.
                """,
            challenge: "R1 must carry at least 20 mA from the 12 V source, but it is a ¼ W resistor. Pick a resistance that meets both limits.",
            goals: [
                .current("R1", .atLeast(20e-3)),
                .power("R1", .atMost(0.25)),
                .keeps("V1", at: 12, unit: "V"),
            ],
            hints: [
                "Each limit bounds R from one side. The current I = V / R ≥ 20 mA, so R ≤ V / 20 mA.",
                "The power P = V² / R ≤ 0.25 W, so R ≥ V² / 0.25 W.",
            ],
            answer: """
                From the current: R ≤ 12 V / 20 mA = 600 Ω. From the power: R ≥ (12 V)² / 0.25 W = 576 Ω. \
                Any resistance from 576 Ω to 600 Ω works: 590 Ω draws 20.3 mA and dissipates 244 mW.
                """,
            starter: Bench.loop(volts: 12, ohms: 220),
            solution: Bench.loop(volts: 12, ohms: 590))
    }

    static var seriesResistors: Lesson {
        // R1 along the top; the top rail continues to x = 26 and turns down to the ground rail.
        func circuit(extraResistors: Int) -> Circuit {
            var b = Bench()
            b.vertical(.voltageSource, "V1", 3, top: GridPoint(6, 6))
            b.wire(GridPoint(6, 6), GridPoint(10, 6))
            var x = 10
            for name in ["R1", "R2", "R3"].prefix(1 + extraResistors) {
                b.horizontal(.resistor, name, 1e3, left: GridPoint(x, 6))
                x += 4
            }
            b.wire(GridPoint(x, 6), GridPoint(26, 6), GridPoint(26, 10), GridPoint(6, 10))
            b.ground(at: GridPoint(6, 10))
            b.circuit.simulation.analysis = .operatingPoint
            return b.circuit
        }
        return Lesson(
            id: "series-resistors", chapter: "DC Circuits", title: "Resistors in Series",
            introduction: """
                Parts in **series** sit one after another on a single path, so the same current flows \
                through each of them. Their resistances add up:

                > R = R1 + R2 + R3 + …

                The source's voltage divides between them. Each resistor takes a share V = I · R, in \
                proportion to its resistance, and the shares add up to the source voltage. This is \
                **Kirchhoff's voltage law**: around any loop, the voltages add up to zero.
                """,
            challenge: "Using only 1 kΩ resistors, make the 3 V source deliver exactly 1 mA.",
            goals: [
                .current("V1", .near(1e-3, tolerance: 0.01), quantity: "Current from V1"),
                .onlyUses(.resistor, value: 1e3),
                .keeps("V1", at: 3, unit: "V"),
            ],
            hints: [
                "What total resistance lets 3 V drive 1 mA?",
                "To make room, click the wire to the right of R1 and delete it (⌫). A part placed on top of a wire is shorted by it.",
                "Select R1 and press ⌘D to duplicate it, then drag the copy into place. Wire the new resistors in a chain from R1 to the right-hand wire.",
            ],
            answer: "R = V / I = 3 V / 1 mA = 3 kΩ: three 1 kΩ resistors in series. Each one drops 1 V.",
            starter: circuit(extraResistors: 0),
            solution: circuit(extraResistors: 2))
    }

    /// V1 between a top rail (y = 6) and a ground rail (y = `bottom`) that run to x = 24, with
    /// 1 kΩ resistors from rail to rail at x = 12, 16, ….
    private static func rails(volts: Double, bottom: Int = 10, resistors: Int) -> Bench {
        var b = Bench()
        b.vertical(.voltageSource, "V1", volts, top: GridPoint(6, 6))
        if bottom > 10 { b.wire(GridPoint(6, 10), GridPoint(6, bottom)) }
        b.wire(GridPoint(6, 6), GridPoint(24, 6))
        b.wire(GridPoint(6, bottom), GridPoint(24, bottom))
        b.ground(at: GridPoint(6, bottom))
        for index in 0..<resistors {
            let x = 12 + 4 * index
            b.vertical(.resistor, "R\(index + 1)", 1e3, top: GridPoint(x, 6))
            if bottom > 10 { b.wire(GridPoint(x, 10), GridPoint(x, bottom)) }
        }
        b.circuit.simulation.analysis = .operatingPoint
        return b
    }

    static var parallelResistors: Lesson {
        Lesson(
            id: "parallel-resistors", chapter: "DC Circuits", title: "Resistors in Parallel",
            introduction: """
                Parts in **parallel** connect across the same two nets, so they all have the same voltage \
                across them. Each one draws its own current, I = V / R, and the source supplies the sum.

                Every parallel path adds current, so it lowers the total resistance:

                > 1 / R = 1 / R1 + 1 / R2 + …

                Two equal resistors in parallel have half the resistance of one; n equal resistors have 1/n of it.
                """,
            challenge: "Using only 1 kΩ resistors, make the 2 V source deliver 6 mA.",
            goals: [
                .current("V1", .near(6e-3, tolerance: 0.01), quantity: "Current from V1"),
                .onlyUses(.resistor, value: 1e3),
                .keeps("V1", at: 2, unit: "V"),
            ],
            hints: [
                "A single 1 kΩ resistor across 2 V draws 2 mA. How many do you need side by side?",
                "Press R, then Space to stand the resistor upright, and click so that its pins land on the two rails, like R1's.",
            ],
            answer: """
                Each 1 kΩ resistor draws 2 V / 1 kΩ = 2 mA, so three in parallel draw 6 mA. Together they \
                act like a single 1 kΩ / 3 = 333 Ω resistor.
                """,
            starter: rails(volts: 2, resistors: 1).circuit,
            solution: rails(volts: 2, resistors: 3).circuit)
    }

    static var combiningResistors: Lesson {
        var solution = rails(volts: 2, bottom: 14, resistors: 1)
        solution.vertical(.resistor, "R2", 1e3, top: GridPoint(18, 6))
        solution.vertical(.resistor, "R3", 1e3, top: GridPoint(18, 10))
        return Lesson(
            id: "combining-resistors", chapter: "DC Circuits", title: "Combining Resistors",
            introduction: """
                Most circuits mix series and parallel connections. To find the total resistance, simplify \
                step by step: replace each group of parallel resistors with its equivalent, add up the ones \
                in series, and repeat.

                For two resistors in parallel, the formula simplifies to "product over sum":

                > R = R1 · R2 / (R1 + R2)

                For example, two 1 kΩ resistors in parallel make 500 Ω, and in series with a third 1 kΩ \
                resistor they make 1.5 kΩ.
                """,
            challenge: "Using only 1 kΩ resistors, make the 2 V source deliver 3 mA.",
            goals: [
                .current("V1", .near(3e-3, tolerance: 0.01), quantity: "Current from V1"),
                .onlyUses(.resistor, value: 1e3),
                .keeps("V1", at: 2, unit: "V"),
            ],
            hints: [
                "The total must be 2 V / 3 mA = 667 Ω: less than one resistor, so something must be in parallel with R1.",
                "1 kΩ in parallel with 2 kΩ gives 1 kΩ · 2 kΩ / 3 kΩ = 667 Ω. How do you make 2 kΩ from 1 kΩ resistors?",
                "Stack two upright resistors pin to pin between the rails, the way R1 and its wire span them.",
            ],
            answer: """
                Two 1 kΩ resistors in series make 2 kΩ. Connected in parallel with R1, they give \
                1 kΩ · 2 kΩ / 3 kΩ = 667 Ω, and the source delivers 2 V / 667 Ω = 3 mA: 2 mA through R1 and \
                1 mA through the pair.
                """,
            starter: rails(volts: 2, bottom: 14, resistors: 1).circuit,
            solution: solution.circuit)
    }

    static var voltageDivider: Lesson {
        Lesson(
            id: "voltage-divider", chapter: "DC Circuits", title: "Voltage Divider",
            introduction: """
                Two resistors in series across a source form a **voltage divider**. The same current flows \
                through both, so the voltage between them is a fixed fraction of the input:

                > Vout = Vin · R2 / (R1 + R2)

                Only the ratio of the resistors sets the output voltage. Their total sets the current the \
                divider draws, I = Vin / (R1 + R2), which is wasted as heat.

                The net between the resistors has a **net label**, "out", so that it is easy to find in the \
                results. Press **N** and click a wire to label a net yourself.
                """,
            challenge: "Make V(out) 3.3 V from the 5 V source, drawing no more than 1 mA from it.",
            goals: [
                .voltage("out", .near(3.3, tolerance: 0.01)),
                .current("V1", .atMost(1e-3), quantity: "Current from V1"),
                .keeps("V1", at: 5, unit: "V"),
            ],
            hints: [
                "3.3 V is 66 % of 5 V, so R2 must be 66 % of the total R1 + R2.",
                "To draw at most 1 mA, the total R1 + R2 must be at least 5 V / 1 mA = 5 kΩ.",
            ],
            answer: """
                Pick a total of 10 kΩ: R2 = 66 % × 10 kΩ = 6.6 kΩ and R1 = 3.4 kΩ, giving 3.3 V and 0.5 mA. \
                Any pair with R2 / (R1 + R2) = 0.66 and R1 + R2 ≥ 5 kΩ works.
                """,
            starter: Bench.ladder(.dc, volts: 5, series: [(.resistor, "R1", 1e3)], shunts: [(.resistor, "R2", 1e3)], analysis: .operatingPoint),
            solution: Bench.ladder(.dc, volts: 5, series: [(.resistor, "R1", 3.4e3)], shunts: [(.resistor, "R2", 6.6e3)], analysis: .operatingPoint))
    }

    static var currentLaw: Lesson {
        func circuit(r2: Double) -> Circuit {
            var b = Bench()
            b.verticalUp(.currentSource, "I1", 6e-3, bottom: GridPoint(6, 10))
            b.wire(GridPoint(6, 6), GridPoint(20, 6))
            b.label("top", at: GridPoint(10, 6))
            b.vertical(.resistor, "R1", 1e3, top: GridPoint(14, 6))
            b.vertical(.resistor, "R2", r2, top: GridPoint(20, 6))
            b.wire(GridPoint(6, 10), GridPoint(20, 10))
            b.ground(at: GridPoint(6, 10))
            b.circuit.simulation.analysis = .operatingPoint
            return b.circuit
        }
        return Lesson(
            id: "current-law", chapter: "DC Circuits", title: "Kirchhoff's Current Law",
            introduction: """
                Charge doesn't pile up anywhere in a circuit, so all the current flowing into a node flows \
                out again. This is **Kirchhoff's current law** (KCL):

                > I_in = I1 + I2 + …

                A **current source** pushes a fixed current in the direction of its arrow, whatever voltage \
                that takes. Here I1 pushes 6 mA up into the net "top", where it splits between R1 and R2. \
                Both resistors have the same voltage across them, so the smaller one takes the larger share.
                """,
            challenge: "Choose R2 so that exactly 4 mA of I1's 6 mA flows through R1.",
            goals: [
                .current("R1", .near(4e-3, tolerance: 0.01)),
                .keeps("I1", at: 6e-3, unit: "A"),
                .keeps("R1", at: 1e3, unit: "Ω"),
            ],
            hints: [
                "By KCL, R2 must carry the remaining 6 mA − 4 mA = 2 mA.",
                "4 mA through R1 = 1 kΩ puts the net \"top\" at 4 V, and R2 has the same 4 V across it.",
            ],
            answer: """
                R2 carries 2 mA with 4 V across it, so R2 = 4 V / 2 mA = 2 kΩ. Check: \
                4 V / 1 kΩ + 4 V / 2 kΩ = 4 mA + 2 mA = 6 mA.
                """,
            starter: circuit(r2: 1e3),
            solution: circuit(r2: 2e3))
    }

    // MARK: - Capacitors and Inductors

    static var rcTimeConstant: Lesson {
        func circuit(r: Double, c: Double) -> Circuit {
            var circuit = Bench.ladder(.step, volts: 5, series: [(.resistor, "R1", r)], shunts: [(.capacitor, "C1", c)], analysis: .transient)
            circuit.simulation.stopTime = 5e-3
            return circuit
        }
        return Lesson(
            id: "rc-time-constant", chapter: "Capacitors and Inductors", title: "The RC Time Constant",
            introduction: """
                A **capacitor** stores charge. Its voltage changes only as current flows in or out: \
                I = C · dV/dt, with the capacitance C in farads (F). Charged through a resistor by a step \
                from 0 V to V, its voltage rises along a curve:

                > V(t) = V · (1 − e^(−t / τ)),  τ = R · C

                The **time constant** τ (tau) is the time it takes to reach 63 % of the final voltage. \
                After 5 τ the capacitor is more than 99 % charged.

                This lesson uses a **transient** analysis, which plots voltages against time. The source \
                steps from 0 V to 5 V at t = 0.
                """,
            challenge: "Make the time constant 1 ms, so that V(out) reaches 63 % of 5 V, 3.16 V, at t = 1 ms.",
            goals: [
                .voltage("out", at: 1e-3, .near(5 * (1 - exp(-1)), tolerance: 0.02), stopTime: 5e-3),
            ],
            hints: [
                "Right now τ = 10 kΩ × 1 µF = 10 ms, ten times too slow.",
                "Change either part so that τ = R · C = 1 ms. Hover over the plot to read V(out) at 1 ms.",
            ],
            answer: """
                τ = R · C = 1 ms. Keeping R1 = 10 kΩ, C1 = 1 ms / 10 kΩ = 100 nF (type **100n**). Keeping \
                C1 = 1 µF and making R1 1 kΩ works just as well.
                """,
            starter: circuit(r: 10e3, c: 1e-6),
            solution: circuit(r: 10e3, c: 100e-9))
    }

    static var inductors: Lesson {
        func circuit(r: Double, l: Double) -> Circuit {
            var circuit = Bench.ladder(.step, volts: 10, series: [(.resistor, "R1", r)], shunts: [(.inductor, "L1", l)], analysis: .transient)
            circuit.simulation.stopTime = 5e-3
            return circuit
        }
        return Lesson(
            id: "inductors", chapter: "Capacitors and Inductors", title: "Inductors",
            introduction: """
                An **inductor**, a coil of wire, stores energy in a magnetic field and opposes changes in \
                its current: V = L · dI/dt, with the inductance L in henries (H). It mirrors a capacitor: \
                a capacitor's voltage can't jump, and an inductor's current can't.

                Switched onto a voltage V through a resistor R, its current rises along the same kind of curve:

                > I(t) = (V / R) · (1 − e^(−t / τ)),  τ = L / R

                Once the current settles, the inductor acts like a plain wire, so the final current is V / R.
                """,
            challenge: "Make the current through L1 settle at 100 mA, and reach 63 % of that, 63.2 mA, at t = 0.5 ms.",
            goals: [
                .current("L1", at: 5e-3, .near(0.1, tolerance: 0.01), stopTime: 5e-3),
                .current("L1", at: 0.5e-3, .near(0.1 * (1 - exp(-1)), tolerance: 0.02), stopTime: 5e-3),
            ],
            hints: [
                "The final current is V / R: choose R1 for 100 mA from 10 V first.",
                "Then τ = L / R = 0.5 ms sets L1.",
            ],
            answer: "R1 = 10 V / 100 mA = 100 Ω. Then L1 = τ · R = 0.5 ms × 100 Ω = 50 mH (type **50m**).",
            starter: circuit(r: 1e3, l: 10e-3),
            solution: circuit(r: 100, l: 50e-3))
    }

    private static func filter(series: Bench.Part, shunts: [Bench.Part], sweep: ClosedRange<Double>, pointsPerDecade: Int = 100) -> Circuit {
        var circuit = Bench.ladder(.sine, volts: 0, series: [series], shunts: shunts, analysis: .ac)
        circuit.simulation.startFrequency = sweep.lowerBound
        circuit.simulation.stopFrequency = sweep.upperBound
        circuit.simulation.pointsPerDecade = pointsPerDecade
        return circuit
    }

    static var lowPassFilter: Lesson {
        Lesson(
            id: "low-pass-filter", chapter: "Capacitors and Inductors", title: "Low-Pass Filter",
            introduction: """
                For alternating current, a capacitor has an **impedance**, its AC resistance, that falls as \
                the frequency f rises:

                > Z = 1 / (2π · f · C)

                In this circuit, low frequencies pass to the output almost untouched, while the capacitor \
                shorts high frequencies to ground. That makes it a **low-pass filter**. Its **cutoff \
                frequency** is where the output falls to 1/√2 (71 %) of the input, called −3 dB:

                > fc = 1 / (2π · R · C)

                The **AC sweep** plots the output against frequency on log scales, in decibels: \
                gain in dB = 20 · log₁₀(Vout / Vin). Every source applies a 1 V signal, so V(out) in dBV is the gain.
                """,
            challenge: "Move the cutoff frequency of this filter to 1 kHz.",
            goals: [
                .cutoff("out", .lowPass, .near(1e3, tolerance: 0.03), sweep: 10...1e6),
            ],
            hints: [
                "Right now fc = 1 / (2π × 1 kΩ × 1 µF) = 159 Hz.",
                "To raise fc about 6.3 times, make R · C 6.3 times smaller.",
            ],
            answer: "R · C = 1 / (2π × 1 kHz) = 159 µs. Keeping R1 = 1 kΩ, C1 = 159 nF (type **159n**).",
            starter: filter(series: (.resistor, "R1", 1e3), shunts: [(.capacitor, "C1", 1e-6)], sweep: 10...1e6),
            solution: filter(series: (.resistor, "R1", 1e3), shunts: [(.capacitor, "C1", 159e-9)], sweep: 10...1e6))
    }

    static var highPassFilter: Lesson {
        Lesson(
            id: "high-pass-filter", chapter: "Capacitors and Inductors", title: "High-Pass Filter",
            introduction: """
                Swap the resistor and the capacitor and the filter turns around. With the capacitor in \
                series with the signal, it blocks low frequencies (and DC entirely) and lets high ones \
                through: a **high-pass filter**, with the same cutoff frequency:

                > fc = 1 / (2π · R · C)

                A series capacitor that blocks DC but passes a signal is also called a **coupling \
                capacitor**. Amplifiers use them between stages.
                """,
            challenge: "Rebuild this low-pass filter as a high-pass filter, with its cutoff at 100 Hz.",
            goals: [
                .cutoff("out", .highPass, .near(100, tolerance: 0.03), sweep: 10...1e6),
            ],
            hints: [
                "Delete R1 and C1. Then put a capacitor along the top where R1 was, and a resistor from \"out\" down to the ground rail where C1 was.",
                "For fc = 100 Hz, R · C = 1 / (2π × 100 Hz) = 1.59 ms.",
            ],
            answer: """
                The capacitor goes in series from "in" to "out", and the resistor from "out" to ground. With \
                R1 = 1 kΩ, C1 = 1.59 ms / 1 kΩ = 1.59 µF (type **1.59u**); or 159 nF with R1 = 10 kΩ.
                """,
            starter: filter(series: (.resistor, "R1", 1e3), shunts: [(.capacitor, "C1", 159e-9)], sweep: 10...1e6),
            solution: filter(series: (.capacitor, "C1", 1.59e-6), shunts: [(.resistor, "R1", 1e3)], sweep: 10...1e6))
    }

    static var resonance: Lesson {
        func circuit(c: Double) -> Circuit {
            filter(series: (.resistor, "R1", 1e3), shunts: [(.inductor, "L1", 1e-3), (.capacitor, "C1", c)], sweep: 100...100e3, pointsPerDecade: 200)
        }
        return Lesson(
            id: "resonance", chapter: "Capacitors and Inductors", title: "Resonance",
            introduction: """
                An inductor's impedance rises with frequency, Z = 2π · f · L, while a capacitor's falls. At \
                one frequency they are equal, and an inductor and a capacitor in parallel stop conducting \
                altogether: energy swings back and forth between them instead. This is **resonance**, at

                > f₀ = 1 / (2π · √(L · C))

                Fed through R1, the parallel LC "tank" shorts every other frequency to ground, so V(out) \
                peaks at f₀. This is a **band-pass filter**: an old-fashioned radio tunes to a station by \
                adjusting one.
                """,
            challenge: "Tune the filter so that its peak is at 10 kHz.",
            goals: [
                .peak("out", .near(10e3, tolerance: 0.02), sweep: 100...100e3),
            ],
            hints: [
                "Right now f₀ = 1 / (2π · √(1 mH × 1 µF)) = 5.03 kHz.",
                "To double f₀, the product L · C must shrink four times. Keep L1 and solve for C: C = 1 / ((2π · f₀)² · L).",
            ],
            answer: """
                With L1 = 1 mH, C1 = 1 / ((2π × 10 kHz)² × 1 mH) = 253 nF (type **253n**). Simply dividing \
                C1 by four, to 250 nF, peaks at 10.07 kHz: close enough.
                """,
            starter: circuit(c: 1e-6),
            solution: circuit(c: 253e-9))
    }

    // MARK: - Semiconductors

    static var diode: Lesson {
        func circuit(r: Double) -> Circuit {
            Bench.ladder(.dc, volts: 5, series: [(.resistor, "R1", r)], shunts: [(.diode, "D1", ComponentKind.diode.defaultValue)], analysis: .operatingPoint)
        }
        return Lesson(
            id: "diode", chapter: "Semiconductors", title: "The Diode",
            introduction: """
                A **diode** lets current flow one way only: from its **anode** to its **cathode**, along the \
                arrow of its symbol. In that forward direction it barely conducts until the voltage across it \
                reaches about **0.6 to 0.7 V** (for silicon); beyond that, the current rises steeply while \
                the voltage hardly changes. In reverse, it blocks.

                So a conducting diode behaves almost like a fixed 0.7 V drop, and something else, usually a \
                series resistor, must limit its current:

                > I ≈ (Vsource − 0.7 V) / R

                Light-emitting diodes (LEDs) work the same way, with a larger drop: about 2 V for a red LED.
                """,
            challenge: "Set the current through the diode to 10 mA.",
            goals: [
                .current("D1", .near(10e-3, tolerance: 0.02)),
                .keeps("V1", at: 5, unit: "V"),
            ],
            hints: [
                "With about 0.7 V across the diode, R1 has the rest: 5 V − 0.7 V = 4.3 V.",
                "V(out) in the DC Op results is the diode's actual forward voltage.",
            ],
            answer: """
                R1 ≈ (5 V − 0.7 V) / 10 mA = 430 Ω. The diode's exact voltage at 10 mA is 0.71 V, so \
                the current comes out at 9.97 mA.
                """,
            starter: circuit(r: 1e3),
            solution: circuit(r: 430))
    }

    static var rectifier: Lesson {
        func circuit(c: Double) -> Circuit {
            var circuit = Bench.ladder(
                .sine, volts: 0, series: [(.diode, "D1", ComponentKind.diode.defaultValue)],
                shunts: [(.capacitor, "C1", c), (.resistor, "R1", 1e3)], analysis: .transient)
            let source = circuit.components.firstIndex { $0.name == "V1" }!
            circuit.components[source].waveform.amplitude = 5
            circuit.components[source].waveform.frequency = 50
            circuit.simulation.stopTime = 100e-3
            return circuit
        }
        return Lesson(
            id: "rectifier", chapter: "Semiconductors", title: "Rectifier",
            introduction: """
                Mains power is AC, but electronics need DC. A **rectifier** converts one into the other. \
                Here D1 conducts only while the input is higher than the output, so it charges C1 on the \
                positive peaks of the 50 Hz sine wave.

                Between peaks, C1 holds the output up while the load R1 slowly drains it, and the output sags \
                by the **ripple** voltage before the next peak tops it up. A bigger capacitor stores more \
                charge, so it sags less:

                > Vripple ≈ Iload / (f · C)

                where f is the frequency of the peaks and Iload ≈ Vout / R1.
                """,
            challenge: "Smooth the output: make the ripple on V(out) smaller than 0.5 V (peak to peak), without changing the load R1.",
            goals: [
                .ripple("out", after: 60e-3, .atMost(0.5), stopTime: 100e-3),
                .keeps("R1", at: 1e3, unit: "Ω"),
            ],
            hints: [
                "The output peaks at about 4.3 V, so the load draws about 4.3 mA.",
                "Solve the ripple formula for the capacitance: C ≈ Iload / (f · Vripple).",
            ],
            answer: """
                C ≈ 4.3 mA / (50 Hz × 0.5 V) = 172 µF. Capacitors come in standard sizes, so take the next \
                one up: 220 µF (type **220u**) leaves about 0.35 V of ripple.
                """,
            starter: circuit(c: 10e-6),
            solution: circuit(c: 220e-6))
    }

    /// An NPN transistor or N-channel MOSFET Q at (20, 11) with its load resistor from the supply
    /// rail (y = 3) to its collector or drain, labeled "out", and its emitter or source on the
    /// ground rail (y = 17). The supply V1 is at x = 28. The base or gate is at (18, 11).
    private static func commonEmitter(_ kind: ComponentKind, _ name: String, supply: Double, load: (name: String, value: Double)) -> Bench {
        var b = Bench()
        b.transistor(kind, name, at: GridPoint(20, 11))
        b.vertical(.resistor, load.name, load.value, top: GridPoint(21, 3))
        b.wire(GridPoint(21, 7), GridPoint(21, 9))
        b.wire(GridPoint(21, 8), GridPoint(24, 8))
        b.label("out", at: GridPoint(24, 8))
        b.vertical(.voltageSource, "V1", supply, top: GridPoint(28, 3))
        b.wire(GridPoint(21, 3), GridPoint(28, 3))
        b.wire(GridPoint(28, 7), GridPoint(28, 17))
        b.wire(GridPoint(21, 13), GridPoint(21, 17))
        b.circuit.simulation.analysis = .operatingPoint
        return b
    }

    static var transistorSwitch: Lesson {
        func circuit(rb: Double) -> Circuit {
            var b = commonEmitter(.bjt, "Q1", supply: 5, load: ("R2", 1e3))
            b.vertical(.voltageSource, "V2", 5, top: GridPoint(8, 11))
            b.wire(GridPoint(8, 11), GridPoint(12, 11))
            b.label("in", at: GridPoint(10, 11))
            b.horizontal(.resistor, "R1", rb, left: GridPoint(12, 11))
            b.wire(GridPoint(16, 11), GridPoint(18, 11))
            b.wire(GridPoint(8, 15), GridPoint(8, 17), GridPoint(28, 17))
            b.ground(at: GridPoint(8, 17))
            return b.circuit
        }
        return Lesson(
            id: "transistor-switch", chapter: "Semiconductors", title: "Transistor as a Switch",
            introduction: """
                A **bipolar junction transistor** (BJT) amplifies current: a small current into its **base** \
                lets a current up to β (beta) times larger flow into its **collector** and out of its \
                **emitter**. Here β = 100. Between base and emitter there's a diode junction, so the base \
                sits about 0.7 V above the emitter.

                To use the transistor as a **switch**, drive it hard: give it so much base current that the \
                collector current is limited only by the load, R2. The transistor is then **saturated**, and \
                its collector drops to about 0.1 V, nearly ground. This is how a microcontroller pin \
                switches an LED, a relay, or a motor.

                Select Q1 to see its operating region in the inspector.
                """,
            challenge: "V2 is a 5 V control signal. Choose R1 so that Q1 saturates and V(out) drops below 0.2 V, while keeping the base current under 1 mA.",
            goals: [
                .region("Q1", BJTModel.Region.saturation),
                .voltage("out", .atMost(0.2)),
                .current("R1", .atMost(1e-3), quantity: "Base current through R1"),
                .keeps("R2", at: 1e3, unit: "Ω"),
                .keeps("V2", at: 5, unit: "V"),
            ],
            hints: [
                "Switched on, R2 has nearly all of the 5 V across it, so the collector current is about 5 V / 1 kΩ = 5 mA.",
                "That takes a base current of at least 5 mA / β = 50 µA. A good switch gets several times more.",
                "The base current is (5 V − 0.7 V) / R1.",
            ],
            answer: """
                For 50 µA, R1 ≤ 4.3 V / 50 µA = 86 kΩ. Designers give a switch 5 to 10 times the minimum \
                base current, so R1 is typically 4.7 kΩ to 10 kΩ: R1 = 10 kΩ gives 0.43 mA of base current \
                and V(out) = 0.07 V.
                """,
            starter: circuit(rb: 1e6),
            solution: circuit(rb: 10e3))
    }

    static var transistorBias: Lesson {
        func circuit(rb: Double, rc: Double) -> Circuit {
            var b = commonEmitter(.bjt, "Q1", supply: 10, load: ("R2", rc))
            b.vertical(.resistor, "R1", rb, top: GridPoint(16, 3))
            b.wire(GridPoint(16, 3), GridPoint(21, 3))
            b.wire(GridPoint(16, 7), GridPoint(16, 11), GridPoint(18, 11))
            b.wire(GridPoint(21, 17), GridPoint(28, 17))
            b.ground(at: GridPoint(21, 17))
            return b.circuit
        }
        return Lesson(
            id: "transistor-bias", chapter: "Semiconductors", title: "Biasing a Transistor",
            introduction: """
                To **amplify** a signal rather than switch it, a transistor must rest in its \
                **forward-active** region: partly on, with room for its collector voltage to swing both up \
                and down. Setting that resting point is called **biasing**.

                In the forward-active region, the collector current is β times the base current:

                > Ic = β · Ib

                and the collector sits at the supply voltage minus the drop across the collector resistor, \
                Vc = Vcc − Ic · Rc. A good resting point puts Vc near half the supply, so the output can \
                swing equally far both ways.
                """,
            challenge: "Bias Q1 at a collector current of 1 mA, with V(out) at 5 V, half the 10 V supply.",
            goals: [
                .region("Q1", BJTModel.Region.active),
                .current("Q1", .near(1e-3, tolerance: 0.05), quantity: "Collector current Ic(Q1)"),
                .voltage("out", .near(5, tolerance: 0.05)),
                .keeps("V1", at: 10, unit: "V"),
            ],
            hints: [
                "Right now R1 feeds about 93 µA into the base, so Q1 tries to draw 9.3 mA and pulls V(out) down to 0.7 V.",
                "For Ic = 1 mA, the base current must be Ic / β = 10 µA. R1 has about 10 V − 0.65 V across it.",
                "R2 must drop the other half of the supply, 5 V, at 1 mA.",
            ],
            answer: """
                Ib = 1 mA / 100 = 10 µA, so R1 = (10 V − 0.65 V) / 10 µA ≈ 935 kΩ, and R2 = 5 V / 1 mA = \
                5 kΩ. This simple bias depends directly on β, which varies widely between real transistors. \
                Practical amplifiers bias the base with a voltage divider and add an emitter resistor, as in \
                the example File ▸ New from Example ▸ BJT Common-Emitter Amplifier.
                """,
            starter: circuit(rb: 100e3, rc: 1e3),
            solution: circuit(rb: 935e3, rc: 5e3))
    }

    static var mosfet: Lesson {
        func circuit(gate: Double) -> Circuit {
            var b = commonEmitter(.mosfet, "M1", supply: 10, load: ("R1", 1e3))
            b.vertical(.voltageSource, "V2", gate, top: GridPoint(12, 11))
            b.wire(GridPoint(12, 11), GridPoint(18, 11))
            b.label("gate", at: GridPoint(15, 11))
            b.wire(GridPoint(12, 15), GridPoint(12, 17), GridPoint(28, 17))
            b.ground(at: GridPoint(12, 17))
            return b.circuit
        }
        return Lesson(
            id: "mosfet", chapter: "Semiconductors", title: "The MOSFET",
            introduction: """
                A **MOSFET** is controlled by voltage instead of current: its **gate** is insulated and draws \
                no current at all. Below its **threshold voltage** Vth, 1 V here, the transistor is off. \
                Above it, current flows from the **drain** to the **source**. In **saturation**, when the \
                drain–source voltage is large enough, the drain current follows the square law:

                > Id = ½ · k · (V_GS − Vth)²

                with k = 2 mA/V² here. MOSFETs are the switches in every digital chip, and the power \
                switches in chargers and motor drives.
                """,
            challenge: "Set the gate voltage V2 so that the drain current is 4 mA, with M1 in saturation.",
            goals: [
                .current("M1", .near(4e-3, tolerance: 0.02), quantity: "Drain current Id(M1)"),
                .region("M1", MOSFETModel.Region.saturation),
                .keeps("R1", at: 1e3, unit: "Ω"),
                .keeps("V1", at: 10, unit: "V"),
            ],
            hints: [
                "Solve the square law for the overdrive voltage: (V_GS − Vth)² = 2 · Id / k.",
                "Saturation needs V_DS ≥ V_GS − Vth. With 4 mA through R1, V_DS = 10 V − 4 V = 6 V.",
            ],
            answer: """
                (V_GS − 1 V)² = 2 × 4 mA / (2 mA/V²) = 4 V², so V_GS = 3 V. Then V_DS = 10 V − 4 mA × 1 kΩ = \
                6 V, comfortably above V_GS − Vth = 2 V.
                """,
            starter: circuit(gate: 2),
            solution: circuit(gate: 3))
    }

    // MARK: - Op-Amps

    static var invertingAmplifier: Lesson {
        let starter = Examples.invertingAmplifier.circuit
        return Lesson(
            id: "inverting-amplifier", chapter: "Op-Amps", title: "Inverting Amplifier",
            introduction: """
                An **operational amplifier** (op-amp) amplifies the difference between its two inputs by an \
                enormous gain A, 100 000 here: Vout = A · (V+ − V−). That is far too much gain to use \
                directly, so op-amps are tamed with **negative feedback**: a path from the output back to \
                the − input.

                With feedback, the op-amp drives its output to whatever keeps V− equal to V+. Here V+ is \
                grounded, so the − input sits at 0 V, a **virtual ground**. All of R1's current, Vin / R1, \
                must continue through R2, so

                > Gain = Vout / Vin = −R2 / R1

                The minus sign means the output is inverted: it falls when the input rises.
                """,
            challenge: "Change the amplifier's gain from −10 to −5.",
            goals: [
                .gain("out", over: "in", at: 1e3, .near(-5, tolerance: 0.02)),
            ],
            hints: [
                "The gain depends only on the ratio R2 / R1.",
                "When you're done, the transient plot shows V(out) upside down relative to V(in), at 5 times its size.",
            ],
            answer: "−R2 / R1 = −5: with R1 = 1 kΩ, R2 = 5 kΩ. Doubling R1 to 2 kΩ works too.",
            starter: starter,
            solution: starter.setting("R2", to: 5e3))
    }

    static var nonInvertingAmplifier: Lesson {
        func circuit(feedback: Bool) -> Circuit {
            var b = Bench()
            var source = SourceWaveform(shape: .sine)
            source.amplitude = 0.1
            b.vertical(.voltageSource, "V1", 0, top: GridPoint(6, 6), waveform: source)
            b.ground(at: GridPoint(6, 10))
            // + input at (18, 6), − input at (18, 4), output at (22, 5).
            b.opAmp("U1", plus: GridPoint(18, 6))
            b.wire(GridPoint(6, 6), GridPoint(18, 6))
            b.label("in", at: GridPoint(10, 6))
            b.wire(GridPoint(22, 5), GridPoint(28, 5))
            b.label("out", at: GridPoint(26, 5))
            if feedback {
                b.wire(GridPoint(18, 4), GridPoint(16, 4), GridPoint(16, 2))
                b.horizontal(.resistor, "R2", 10e3, left: GridPoint(16, 2))
                b.wire(GridPoint(20, 2), GridPoint(24, 2), GridPoint(24, 5))
                b.horizontal(.resistor, "R1", 1e3, left: GridPoint(12, 4))
                b.ground(at: GridPoint(12, 4))
            }
            b.circuit.simulation.analysis = .transient
            b.circuit.simulation.stopTime = 3e-3
            return b.circuit
        }
        return Lesson(
            id: "non-inverting-amplifier", chapter: "Op-Amps", title: "Non-Inverting Amplifier",
            introduction: """
                Feed the signal into the **+ input** instead, and the amplifier no longer inverts. The \
                feedback network now runs from the output, through R2 to the − input, and through R1 to \
                ground. It's a voltage divider that feeds a fraction of the output back, and the op-amp \
                makes that fraction equal to the input:

                > Gain = 1 + R2 / R1

                Without any feedback, as in this circuit, the op-amp amplifies by its full gain of 100 000. \
                The simulated output swings by ±10 kV; a real op-amp would simply stop at its supply voltages.
                """,
            challenge: "Add feedback resistors to make a non-inverting amplifier with a gain of 11.",
            goals: [
                .gain("out", over: "in", at: 1e3, .near(11, tolerance: 0.02)),
            ],
            hints: [
                "One resistor goes from the output to the − input; the other from the − input to ground. You can place another ground symbol anywhere.",
                "1 + R2 / R1 = 11, so R2 = 10 × R1.",
            ],
            answer: """
                R2 = 10 kΩ from "out" to the − input, and R1 = 1 kΩ from the − input to ground: the gain is \
                1 + 10 kΩ / 1 kΩ = 11.
                """,
            starter: circuit(feedback: false),
            solution: circuit(feedback: true))
    }

    // MARK: - Digital Logic

    private static let twoInputs = [(name: "A", source: "VA"), (name: "B", source: "VB")]

    static var logicGates: Lesson {
        func circuit(invertB: Bool) -> Circuit {
            var b = Bench()
            b.logicInput("VA", "a", top: GridPoint(2, 3), to: GridPoint(12, 3), bit: 0, of: 2)
            b.wire(GridPoint(12, 3), GridPoint(12, 7), GridPoint(14, 7))
            b.gate(.and, "U1", at: GridPoint(16, 8))
            if invertB {
                b.logicInput("VB", "b", top: GridPoint(2, 13), to: GridPoint(8, 13), bit: 1, of: 2)
                b.gate(.not, "U2", at: GridPoint(10, 13))
            } else {
                b.logicInput("VB", "b", top: GridPoint(2, 13), to: GridPoint(12, 13), bit: 1, of: 2)
            }
            b.wire(GridPoint(12, 13), GridPoint(12, 9), GridPoint(14, 9))
            b.wire(GridPoint(18, 8), GridPoint(24, 8))
            b.label("y", at: GridPoint(22, 8))
            b.countThrough(inputs: 2)
            return b.circuit
        }
        return Lesson(
            id: "logic-gates", chapter: "Digital Logic", title: "Logic Gates",
            introduction: """
                Digital circuits work with just two levels: a voltage near the supply stands for **1**, and \
                one near 0 V for **0**. A **logic gate** computes a 1 or a 0 from its inputs:

                **NOT** inverts its input.
                **AND** is 1 only when both inputs are 1.
                **OR** is 1 when either input is 1.
                **XOR** is 1 when the inputs differ.
                **NAND**, **NOR**, and **XNOR** are AND, OR, and XOR inverted. A bubble on a gate's output means NOT.

                A **truth table** lists the output for every combination of inputs. For an AND gate:

                > A B → y:   00 → 0,   01 → 0,   10 → 0,   11 → 1

                These gates run on 5 V: their outputs are 0 V or 5 V, and their inputs switch at 2.5 V. The \
                sources VA and VB count through the four combinations, a millisecond each, so the plot steps \
                through the truth table. Press **A** to place a logic gate, and pick its function in the inspector.
                """,
            challenge: "Make y 1 only when A is 1 and B is 0.",
            goals: [
                .truthTable("y", inputs: twoInputs, "y = A AND NOT B, for every input") { $0[0] && !$0[1] },
            ],
            hints: [
                "The truth table you want is 00 → 0, 01 → 0, 10 → 1, 11 → 0: A AND the opposite of B.",
                "Invert B with a NOT gate before it reaches U1. Delete the wire from b to U1 to make room.",
                "Press A and click to place a gate, then pick NOT in the inspector. A NOT gate's input and output are in line, like a resistor's pins.",
            ],
            answer: """
                Feed B through a NOT gate into U1's lower input: y = A AND (NOT B). In the plot, y is high \
                only in the third millisecond, while A = 1 and B = 0.
                """,
            starter: circuit(invertB: false),
            solution: circuit(invertB: true))
    }

    static var nandUniversal: Lesson {
        var starter = Bench()
        starter.logicInput("VA", "a", top: GridPoint(2, 3), to: GridPoint(12, 3), bit: 0, of: 2)
        starter.logicInput("VB", "b", top: GridPoint(2, 13), to: GridPoint(12, 13), bit: 1, of: 2)
        starter.gate(.nand, "U1", at: GridPoint(16, 8))
        starter.wire(GridPoint(12, 3), GridPoint(12, 7), GridPoint(14, 7))
        starter.wire(GridPoint(12, 13), GridPoint(12, 9), GridPoint(14, 9))
        starter.wire(GridPoint(18, 8), GridPoint(38, 8))
        starter.label("y", at: GridPoint(37, 8))
        starter.countThrough(inputs: 2)
        var solution = Bench()
        solution.xorFromNAND()
        solution.countThrough(inputs: 2)
        return Lesson(
            id: "nand-universal", chapter: "Digital Logic", title: "NAND Is Universal",
            introduction: """
                **NAND**, NOT-AND, is 0 only when both of its inputs are 1. It is **universal**: every other \
                logic function can be built from NAND gates alone. With its inputs tied together, a NAND gate \
                is a NOT gate, and a NAND followed by a NOT is an AND.

                **XOR**, exclusive or, is 1 when its inputs differ:

                > A B → y:   00 → 0,   01 → 1,   10 → 1,   11 → 0

                It takes four NAND gates. Chips are built mostly from NAND gates, because a CMOS NAND gate \
                needs only four transistors.
                """,
            challenge: "Using only NAND gates, make y = A XOR B.",
            goals: [
                .truthTable("y", inputs: twoInputs, "y = A XOR B, for every input") { $0[0] != $0[1] },
                .onlyGates(.nand),
            ],
            hints: [
                "U1 computes n = NAND(A, B), which is 0 only when both inputs are 1.",
                "NAND(A, n) is 0 only when A is 1 and B is 0. NAND(n, B) is 0 only when B is 1 and A is 0.",
                "A fourth NAND of those two is 1 when either of them is 0: that's y. Delete the wire from U1 to y first, and duplicate U1 (⌘D) for the new gates.",
            ],
            answer: """
                With n = NAND(A, B), y = NAND(NAND(A, n), NAND(n, B)): four NAND gates. Dive into an XOR \
                gate to see this circuit, or into a NAND gate to see its four transistors.
                """,
            starter: starter.circuit,
            solution: solution.circuit)
    }

    static var binaryAddition: Lesson {
        let inputs = twoInputs + [(name: "Cin", source: "VC")]
        var starter = Bench()
        starter.halfAdder(inputs: 3)
        starter.wire(GridPoint(20, 4), GridPoint(40, 4))
        starter.label("s", at: GridPoint(39, 4))
        starter.wire(GridPoint(20, 10), GridPoint(42, 10))
        starter.label("cout", at: GridPoint(41, 10))
        starter.logicInput("VC", "cin", top: GridPoint(2, 21), bit: 2, of: 3)
        starter.countThrough(inputs: 3)

        // U1's output p = A XOR B feeds U3 = XOR(p, cin), the sum, and U4 = AND(p, cin). U5 ORs
        // U4 with U2 = AND(A, B) into the carry out.
        var solution = Bench()
        solution.halfAdder(inputs: 3)
        solution.logicInput("VC", "cin", top: GridPoint(2, 21), to: GridPoint(24, 21), bit: 2, of: 3)
        solution.gate(.xor, "U3", at: GridPoint(28, 6))
        solution.gate(.and, "U4", at: GridPoint(28, 14))
        solution.gate(.or, "U5", at: GridPoint(36, 12))
        solution.wire(GridPoint(20, 4), GridPoint(22, 4), GridPoint(22, 13), GridPoint(26, 13))
        solution.wire(GridPoint(22, 5), GridPoint(26, 5))
        solution.wire(GridPoint(24, 21), GridPoint(24, 7), GridPoint(26, 7))
        solution.wire(GridPoint(24, 15), GridPoint(26, 15))
        solution.wire(GridPoint(30, 6), GridPoint(40, 6))
        solution.label("s", at: GridPoint(39, 6))
        solution.wire(GridPoint(20, 10), GridPoint(32, 10), GridPoint(32, 11), GridPoint(34, 11))
        solution.wire(GridPoint(30, 14), GridPoint(32, 14), GridPoint(32, 13), GridPoint(34, 13))
        solution.wire(GridPoint(38, 12), GridPoint(42, 12))
        solution.label("cout", at: GridPoint(41, 12))
        solution.countThrough(inputs: 3)
        return Lesson(
            id: "binary-addition", chapter: "Digital Logic", title: "Binary Addition",
            introduction: """
                Adding two bits gives a two-bit result: 0 + 1 = 01, and 1 + 1 = 10. The low bit, the \
                **sum**, is A XOR B; the high bit, the **carry**, is A AND B. Those two gates make a \
                **half adder**: the circuit here.

                To add numbers of many bits, each column must also add the carry from the column to its \
                right, as in long addition. A **full adder** adds three bits, A, B, and a carry in, Cin:

                > s = A XOR B XOR Cin

                > cout = (A AND B) OR (Cin AND (A XOR B))

                The carry out is 1 when at least two of the three inputs are. Chain 64 full adders, each \
                one's carry out into the next one's carry in, and you have the adder of a 64-bit processor.
                """,
            challenge: "Extend the half adder into a full adder, so that s and cout include the carry in, Cin.",
            goals: [
                .truthTable("s", inputs: inputs, "s = A XOR B XOR Cin, for every input") { $0.filter { $0 }.count % 2 == 1 },
                .truthTable("cout", inputs: inputs, "cout = 1 when two or more inputs are 1") { $0.filter { $0 }.count >= 2 },
            ],
            hints: [
                "U1's output, A XOR B, is the sum before the carry in. XOR it with Cin to get s.",
                "There's a carry out when A and B are both 1 (that's U2), or when Cin is 1 and exactly one of A and B is: Cin AND (A XOR B).",
                "OR those two carries together for cout. In all you need two XOR gates, two AND gates, and an OR gate.",
            ],
            answer: """
                s = (A XOR B) XOR Cin, and cout = (A AND B) OR (Cin AND (A XOR B)). A new XOR gate after U1 \
                gives the sum; U2 and a new AND gate give the two ways to carry, and an OR gate combines \
                them. A full adder is two half adders and an OR gate.
                """,
            starter: starter.circuit,
            solution: solution.circuit)
    }

    static var srLatch: Lesson {
        Lesson(
            id: "sr-latch", chapter: "Digital Logic", title: "The SR Latch",
            introduction: """
                Each gate so far computes its output from its inputs alone, so it forgets them the moment \
                they change. Memory needs **feedback**: an output fed back into an input.

                Cross-couple two NOR gates, each one's output into one input of the other, and you have an \
                **SR latch**. While both its inputs are 0, it holds whichever state it is in: q = 1 and \
                qbar = 0, or the other way around. A pulse on **S**, set, makes q = 1; a pulse on **R**, \
                reset, makes q = 0. After the pulse, the latch remembers.

                Here R pulses at the start and again at 3 ms, and S pulses at 1 ms. Each gate's second \
                input is grounded, so for now q is just NOT R.
                """,
            challenge: "Replace the grounds with feedback, qbar into U1 and q into U2, so that q remembers each pulse.",
            goals: [
                .voltage("q", at: 0.8e-3, .atMost(0.5), stopTime: 5e-3),
                .voltage("q", at: 2.5e-3, .atLeast(4.5), stopTime: 5e-3),
                .voltage("q", at: 4.5e-3, .atMost(0.5), stopTime: 5e-3),
            ],
            hints: [
                "Delete the ground symbols on U1's lower input and U2's upper input.",
                "Wire q, U1's output, to U2's upper input, and qbar, U2's output, to U1's lower input. Wires that cross without a dot aren't connected.",
                "Instead of drawing wires, you can put net labels named q and qbar on the inputs: labels with the same name are connected.",
            ],
            answer: """
                With each output fed back, S's pulse at 1 ms sets the latch, and it keeps q = 1 until R's \
                pulse at 3 ms resets it. V(q) is high from 1 ms to 3 ms, not just during the pulse.
                """,
            starter: Bench.srLatch(feedback: false),
            solution: Bench.srLatch(feedback: true))
    }

    static var propagationDelay: Lesson {
        func circuit(inverters: Int) -> Circuit {
            var b = Bench()
            var enable = SourceWaveform(shape: .step)
            enable.delay = 50e-9
            b.vertical(.voltageSource, "VEN", 5, top: GridPoint(2, 5), waveform: enable)
            b.ground(at: GridPoint(2, 9))
            b.wire(GridPoint(2, 5), GridPoint(12, 5))
            b.label("en", at: GridPoint(5, 5))
            b.gate(.nand, "U1", at: GridPoint(14, 6))
            var x = 16
            for index in 0..<inverters {
                b.wire(GridPoint(x, 6), GridPoint(x + 2, 6))
                b.gate(.not, "U\(index + 2)", at: GridPoint(x + 4, 6))
                x += 6
            }
            b.wire(GridPoint(x, 6), GridPoint(x + 4, 6), GridPoint(x + 4, 10), GridPoint(10, 10), GridPoint(10, 7), GridPoint(12, 7))
            b.label("out", at: GridPoint(x + 2, 6))
            b.circuit.simulation.analysis = .transient
            b.circuit.simulation.stopTime = 500e-9
            return b.circuit
        }
        return Lesson(
            id: "propagation-delay", chapter: "Digital Logic", title: "Propagation Delay",
            introduction: """
                A gate doesn't respond instantly. Its transistors must charge the inputs of the next gates, \
                which are small capacitors, and that takes a **propagation delay**, t_pd: 10 ns for the \
                gates here, like a 74HC logic chip, and a few picoseconds inside a processor.

                Delay limits how fast a circuit can run, but it can also be put to work. Connect an odd \
                number of inverting gates in a ring and no state is stable: each gate flips the next, and \
                the change runs around the ring forever. The output completes a cycle after the change has \
                gone around twice, so a **ring oscillator** of N gates runs at

                > f = 1 / (2 · N · t_pd)

                U1 is a NAND gate that acts as an inverter once its other input, en, rises at 50 ns. Until \
                then it holds the ring still. Hover over the plot to read the times of V(out)'s edges.
                """,
            challenge: "The ring of three gates oscillates at about 17 MHz. Slow it down to 10 MHz.",
            goals: [
                .frequency("out", after: 150e-9, .near(10e6, tolerance: 0.05), stopTime: 500e-9),
            ],
            hints: [
                "With t_pd = 10 ns, f = 1 / (2 · N · 10 ns). How many gates make 10 MHz?",
                "Add two more NOT gates to the ring. The ring needs an odd number of inverting gates, or it settles instead of oscillating.",
                "Or keep three gates, and lengthen each one's propagation delay in the inspector.",
            ],
            answer: """
                1 / (2 · N · 10 ns) = 10 MHz gives N = 5: add two NOT gates to the ring. Keeping three gates \
                and giving each a propagation delay of 16.7 ns works too.
                """,
            starter: circuit(inverters: 2),
            solution: circuit(inverters: 4))
    }

    static var cmosGates: Lesson {
        var starter = Bench()
        starter.transistor(.mosfet, "M2", .p, at: GridPoint(18, 6))
        starter.transistor(.mosfet, "M1", at: GridPoint(18, 14))
        starter.wire(GridPoint(19, 4), GridPoint(19, 2))
        starter.label("vdd", at: GridPoint(26, 2))
        starter.wire(GridPoint(19, 8), GridPoint(19, 12))
        starter.wire(GridPoint(19, 10), GridPoint(37, 10))
        starter.label("y", at: GridPoint(36, 10))
        starter.wire(GridPoint(19, 16), GridPoint(19, 24))
        starter.ground(at: GridPoint(19, 24))
        starter.gateLabel("a", at: GridPoint(16, 6))
        starter.gateLabel("a", at: GridPoint(16, 14))
        starter.supply(at: GridPoint(42, 2), from: GridPoint(19, 2))
        starter.logicInput("VA", "a", top: GridPoint(2, 8), bit: 0, of: 2)
        starter.logicInput("VB", "b", top: GridPoint(2, 16), bit: 1, of: 2)
        starter.countThrough(inputs: 2)
        return Lesson(
            id: "cmos-gates", chapter: "Digital Logic", title: "Gates from Transistors",
            introduction: """
                Inside every CMOS logic gate are MOSFETs used as switches. An n-channel MOSFET conducts \
                when its gate is high; a p-channel MOSFET conducts when its gate is low.

                This circuit is a **CMOS inverter**, a NOT gate. When A is low, M2 (p-channel) connects y \
                to the 5 V supply, vdd. When A is high, M1 (n-channel) connects y to ground. One of them is \
                always off, so no current flows at rest.

                A **NAND** gate needs two more transistors. Its output must fall only when A **and** B are \
                high, so its n-channel transistors are in **series**. It must rise when A **or** B is low, \
                so its p-channel transistors are in **parallel**.
                """,
            challenge: "Turn the inverter into a NAND gate of A and B, built from MOSFETs.",
            goals: [
                .truthTable("y", inputs: twoInputs, "y = A NAND B, for every input") { !($0[0] && $0[1]) },
                .avoids(.logicGate, "Use MOSFETs, not logic gates"),
            ],
            hints: [
                "Add an n-channel MOSFET in series with M1, between M1's source and ground: delete the wire from M1 to ground first. Its gate goes to b.",
                "Add a p-channel MOSFET in parallel with M2, from vdd to y. Pick P-channel in the inspector: it's drawn upside down, with its source on top.",
                "Connect the new transistors' gates to b with wires, or with net labels named b, like the labels a on M1 and M2.",
            ],
            answer: """
                An n-channel MOSFET with its gate on b goes between M1's source and ground, and a p-channel \
                one with its gate on b from vdd to y, beside M2. Dive into a NAND gate to see this circuit.
                """,
            starter: starter.circuit,
            solution: DiveInCircuits.cmosGate(.nand))
    }
}

// MARK: - Layout

/// Builds circuits on explicit grid coordinates, for the tutorial and Dive In.
struct Bench {
    typealias Part = (kind: ComponentKind, name: String, value: Double)

    var circuit = Circuit()

    /// An upright two-terminal part with pin 1 at `top` and pin 2 four units below.
    mutating func vertical(_ kind: ComponentKind, _ name: String, _ value: Double, top: GridPoint, waveform: SourceWaveform = SourceWaveform()) {
        circuit.components.append(Component(kind: kind, name: name, position: top + GridPoint(0, 2), rotation: 1, value: value, waveform: waveform))
    }

    /// An upright two-terminal part with pin 1 at `bottom`: a current source pushing upward.
    mutating func verticalUp(_ kind: ComponentKind, _ name: String, _ value: Double, bottom: GridPoint) {
        circuit.components.append(Component(kind: kind, name: name, position: bottom - GridPoint(0, 2), rotation: 3, value: value))
    }

    /// A horizontal two-terminal part with pin 1 at `left` and pin 2 four units right.
    mutating func horizontal(_ kind: ComponentKind, _ name: String, _ value: Double, left: GridPoint) {
        circuit.components.append(Component(kind: kind, name: name, position: left + GridPoint(2, 0), rotation: 0, value: value))
    }

    /// A transistor at `position` with its base or gate at + (−2, 0). An N-type device has its
    /// collector or drain at + (1, −2) and its emitter or source at + (1, 2); a P-type one is upside down.
    mutating func transistor(_ kind: ComponentKind, _ name: String, _ polarity: TransistorParameters.Polarity = .n, at position: GridPoint) {
        circuit.components.append(Component(
            kind: kind, name: name, position: position, rotation: 0, transistor: TransistorParameters(polarity: polarity)))
    }

    /// An op-amp pointing right with its + input at `plus`, − input two rows up, and output at plus + (4, −1).
    mutating func opAmp(_ name: String, plus: GridPoint) {
        circuit.components.append(Component(kind: .opAmp, name: name, position: plus + GridPoint(2, -1), rotation: 0))
    }

    /// A logic gate pointing right at `position`: a two-input gate's inputs are at + (−2, −1) and
    /// + (−2, 1), a NOT gate's at + (−2, 0), and its output is at + (2, 0).
    mutating func gate(_ function: LogicFunction, _ name: String, at position: GridPoint) {
        circuit.components.append(Component(
            kind: .logicGate, name: name, position: position, rotation: 0, logic: LogicParameters(function: function)))
    }

    /// Logic input `net`: a 5 V source named `name` from `top` down to ground, which counts as bit
    /// `bit` of `count` (see `counting`), and a wire from its + terminal to `end`, labeled three
    /// columns along. By default the wire ends at the label.
    mutating func logicInput(_ name: String, _ net: String, top: GridPoint, to end: GridPoint? = nil, bit: Int, of count: Int) {
        vertical(.voltageSource, name, 5, top: top, waveform: Self.counting(bit: bit, of: count))
        ground(at: top + GridPoint(0, 4))
        wire(top, end ?? top + GridPoint(3, 0))
        label(net, at: top + GridPoint(3, 0))
    }

    /// A pulse train for bit `bit` (0 is the most significant) of `count` inputs that count through
    /// every combination, from all 0s to all 1s, one millisecond each.
    static func counting(bit: Int, of count: Int) -> SourceWaveform {
        var waveform = SourceWaveform(shape: .pulse)
        waveform.period = Double(1 << (count - bit)) * 1e-3
        waveform.delay = waveform.period / 2
        waveform.pulseWidth = waveform.period / 2
        return waveform
    }

    /// A transient analysis over every combination of `count` inputs made by `logicInput`.
    mutating func countThrough(inputs count: Int) {
        circuit.simulation.analysis = .transient
        circuit.simulation.stopTime = Double(1 << count) * 1e-3
    }

    /// A 5 V supply V1 from `top` down to ground, wired to the supply rail at `rail`.
    mutating func supply(at top: GridPoint, from rail: GridPoint) {
        var waveform = SourceWaveform()
        waveform.acMagnitude = 0
        vertical(.voltageSource, "V1", 5, top: top, waveform: waveform)
        wire(rail, top)
        ground(at: top + GridPoint(0, 4))
    }

    /// A short wire from a transistor's gate at `pin`, two columns left to a label `net`.
    mutating func gateLabel(_ net: String, at pin: GridPoint) {
        wire(pin, pin - GridPoint(2, 0))
        label(net, at: pin - GridPoint(2, 0))
    }

    /// A CMOS NAND gate between the rail vdd (y = 2) and ground: M2 and M4 (p-channel, gates at
    /// (16, 6) and (30, 6)) in parallel from vdd to the output, and M1 above M3 (n-channel, gates
    /// at (16, 14) and (16, 20)) in series from the output to ground. A drives M1 and M2, B drives
    /// M3 and M4, and each gate is labeled with its input. The output runs from (33, 10) right to
    /// `outputEnd`, labeled `output` at x = 36.
    mutating func cmosNAND(output: String = "y", outputEnd: Int = 37) {
        transistor(.mosfet, "M2", .p, at: GridPoint(18, 6))
        transistor(.mosfet, "M4", .p, at: GridPoint(32, 6))
        transistor(.mosfet, "M1", at: GridPoint(18, 14))
        transistor(.mosfet, "M3", at: GridPoint(18, 20))
        wire(GridPoint(19, 4), GridPoint(19, 2), GridPoint(33, 2), GridPoint(33, 4))
        label("vdd", at: GridPoint(26, 2))
        wire(GridPoint(19, 8), GridPoint(19, 10), GridPoint(33, 10), GridPoint(33, 8))
        wire(GridPoint(33, 10), GridPoint(outputEnd, 10))
        label(output, at: GridPoint(36, 10))
        wire(GridPoint(19, 10), GridPoint(19, 12))
        wire(GridPoint(19, 16), GridPoint(19, 18))
        wire(GridPoint(19, 22), GridPoint(19, 24))
        ground(at: GridPoint(19, 24))
        gateLabel("a", at: GridPoint(16, 6))
        gateLabel("b", at: GridPoint(30, 6))
        gateLabel("a", at: GridPoint(16, 14))
        gateLabel("b", at: GridPoint(16, 20))
    }

    /// A CMOS NOR gate: M2 above M4 (p-channel) in series from the rail vdd at (19, 2) to the
    /// output y, and M1 and M3 (n-channel) side by side from y to ground. A drives M1 and M2, and B
    /// drives M3 and M4.
    mutating func cmosNOR() {
        transistor(.mosfet, "M2", .p, at: GridPoint(18, 6))
        transistor(.mosfet, "M4", .p, at: GridPoint(18, 12))
        transistor(.mosfet, "M1", at: GridPoint(18, 20))
        transistor(.mosfet, "M3", at: GridPoint(32, 20))
        wire(GridPoint(19, 4), GridPoint(19, 2))
        label("vdd", at: GridPoint(19, 2))
        wire(GridPoint(19, 8), GridPoint(19, 10))
        wire(GridPoint(19, 14), GridPoint(19, 18))
        wire(GridPoint(19, 16), GridPoint(33, 16), GridPoint(33, 18))
        wire(GridPoint(33, 16), GridPoint(37, 16))
        label("y", at: GridPoint(36, 16))
        wire(GridPoint(19, 22), GridPoint(19, 24), GridPoint(33, 24), GridPoint(33, 22))
        ground(at: GridPoint(19, 24))
        gateLabel("a", at: GridPoint(16, 6))
        gateLabel("b", at: GridPoint(16, 12))
        gateLabel("a", at: GridPoint(16, 20))
        gateLabel("b", at: GridPoint(30, 20))
    }

    /// Inputs A (top, y = 3) and B (bottom, y = 13) counting through 00 to 11, and XOR from four
    /// NAND gates: U1 computes n = NAND(a, b), U2 = NAND(a, n), U3 = NAND(n, b), and U4 = NAND(U2, U3) drives y.
    mutating func xorFromNAND() {
        logicInput("VA", "a", top: GridPoint(2, 3), to: GridPoint(22, 3), bit: 0, of: 2)
        logicInput("VB", "b", top: GridPoint(2, 13), to: GridPoint(22, 13), bit: 1, of: 2)
        gate(.nand, "U1", at: GridPoint(16, 8))
        gate(.nand, "U2", at: GridPoint(24, 4))
        gate(.nand, "U3", at: GridPoint(24, 12))
        gate(.nand, "U4", at: GridPoint(32, 8))
        wire(GridPoint(12, 3), GridPoint(12, 7), GridPoint(14, 7))
        wire(GridPoint(12, 13), GridPoint(12, 9), GridPoint(14, 9))
        wire(GridPoint(18, 8), GridPoint(20, 8))
        wire(GridPoint(22, 5), GridPoint(20, 5), GridPoint(20, 11), GridPoint(22, 11))
        wire(GridPoint(26, 4), GridPoint(28, 4), GridPoint(28, 7), GridPoint(30, 7))
        wire(GridPoint(26, 12), GridPoint(28, 12), GridPoint(28, 9), GridPoint(30, 9))
        wire(GridPoint(34, 8), GridPoint(38, 8))
        label("y", at: GridPoint(37, 8))
    }

    /// Wires through `points` in turn.
    mutating func wire(_ points: GridPoint...) {
        for (start, end) in zip(points, points.dropFirst()) {
            circuit.wires.append(Wire(start: start, end: end))
        }
    }

    mutating func ground(at point: GridPoint) {
        circuit.components.append(Component(kind: .ground, name: "GND", position: point))
    }

    mutating func label(_ name: String, at point: GridPoint) {
        circuit.components.append(Component(kind: .netLabel, name: name, position: point))
    }

    /// Inputs A (y = 3) and B (y = 13), bits 0 and 1 of `count`, into a half adder: U1 = XOR(a, b)
    /// with its output at (20, 4) and U2 = AND(a, b) with its output at (20, 10).
    mutating func halfAdder(inputs count: Int) {
        logicInput("VA", "a", top: GridPoint(2, 3), to: GridPoint(16, 3), bit: 0, of: count)
        logicInput("VB", "b", top: GridPoint(2, 13), to: GridPoint(14, 13), bit: 1, of: count)
        gate(.xor, "U1", at: GridPoint(18, 4))
        gate(.and, "U2", at: GridPoint(18, 10))
        wire(GridPoint(12, 3), GridPoint(12, 9), GridPoint(16, 9))
        wire(GridPoint(14, 13), GridPoint(14, 5), GridPoint(16, 5))
        wire(GridPoint(14, 11), GridPoint(16, 11))
    }

    /// An SR latch of NOR gates: U1 = NOR(r, qbar) drives q, and U2 = NOR(q, s) drives qbar. R
    /// pulses at the start and at 3 ms, and S at 1 ms. Without `feedback`, the inputs that would
    /// take qbar and q are grounded instead.
    static func srLatch(feedback: Bool) -> Circuit {
        var b = Bench()
        var reset = SourceWaveform(shape: .pulse)
        reset.period = 3e-3
        var set = SourceWaveform(shape: .pulse)
        set.delay = 1e-3
        set.period = 10e-3
        b.vertical(.voltageSource, "VR", 5, top: GridPoint(2, 3), waveform: reset)
        b.ground(at: GridPoint(2, 7))
        b.wire(GridPoint(2, 3), GridPoint(12, 3))
        b.label("r", at: GridPoint(6, 3))
        b.vertical(.voltageSource, "VS", 5, top: GridPoint(2, 13), waveform: set)
        b.ground(at: GridPoint(2, 17))
        b.wire(GridPoint(2, 13), GridPoint(12, 13))
        b.label("s", at: GridPoint(6, 13))
        b.gate(.nor, "U1", at: GridPoint(14, 4))
        b.gate(.nor, "U2", at: GridPoint(14, 12))
        b.wire(GridPoint(16, 4), GridPoint(22, 4))
        b.label("q", at: GridPoint(21, 4))
        b.wire(GridPoint(16, 12), GridPoint(22, 12))
        b.label("qbar", at: GridPoint(21, 12))
        if feedback {
            b.wire(GridPoint(18, 4), GridPoint(18, 7), GridPoint(10, 7), GridPoint(10, 11), GridPoint(12, 11))
            b.wire(GridPoint(18, 12), GridPoint(18, 9), GridPoint(9, 9), GridPoint(9, 5), GridPoint(12, 5))
        } else {
            b.ground(at: GridPoint(12, 5))
            b.ground(at: GridPoint(12, 11))
        }
        b.circuit.simulation.analysis = .transient
        b.circuit.simulation.stopTime = 5e-3
        return b.circuit
    }

    /// V1 and R1 side by side, joined top and bottom, with ground at the bottom of V1.
    static func loop(volts: Double, ohms: Double) -> Circuit {
        var b = Bench()
        b.vertical(.voltageSource, "V1", volts, top: GridPoint(6, 6))
        b.vertical(.resistor, "R1", ohms, top: GridPoint(14, 6))
        b.wire(GridPoint(6, 6), GridPoint(14, 6))
        b.wire(GridPoint(6, 10), GridPoint(14, 10))
        b.ground(at: GridPoint(6, 10))
        b.circuit.simulation.analysis = .operatingPoint
        return b.circuit
    }

    /// Source V1 at x = 6 from the top rail (y = 6) to the ground rail (y = 10), `series` parts along
    /// the top rail from x = 10, then `shunts` from the top rail to the ground rail, six columns
    /// apart. The source's net is labeled "in" and the net after the series parts "out".
    static func ladder(
        _ shape: SourceWaveform.Shape, volts: Double, series: [Part], shunts: [Part], analysis: SimulationSettings.Analysis
    ) -> Circuit {
        var b = Bench()
        var source = SourceWaveform(shape: shape)
        if shape == .sine { source.amplitude = 1 }
        b.vertical(.voltageSource, "V1", volts, top: GridPoint(6, 6), waveform: source)
        b.wire(GridPoint(6, 6), GridPoint(10, 6))
        b.label("in", at: GridPoint(8, 6))
        var x = 10
        for part in series {
            b.horizontal(part.kind, part.name, part.value, left: GridPoint(x, 6))
            x += 4
        }
        let end = x + 6 * shunts.count
        b.wire(GridPoint(x, 6), GridPoint(end, 6))
        b.label("out", at: GridPoint(x + 3, 6))
        for (index, part) in shunts.enumerated() {
            b.vertical(part.kind, part.name, part.value, top: GridPoint(x + 6 * (index + 1), 6))
        }
        b.wire(GridPoint(6, 10), GridPoint(end, 10))
        b.ground(at: GridPoint(6, 10))
        b.circuit.simulation.analysis = analysis
        return b.circuit
    }
}

extension Circuit {
    /// A copy with the value of the part named `name` changed.
    fileprivate func setting(_ name: String, to value: Double) -> Circuit {
        var circuit = self
        if let index = circuit.components.firstIndex(where: { $0.name == name }) {
            circuit.components[index].value = value
        }
        return circuit
    }
}
