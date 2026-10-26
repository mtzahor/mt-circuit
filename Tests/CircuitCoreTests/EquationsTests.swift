import Foundation
import Testing
@testable import CircuitCore

private func equations(
    _ example: Examples.Example, _ analysis: SimulationSettings.Analysis,
    method: SimulationSettings.IntegrationMethod = .trapezoidal, notation: CircuitEquations.Notation = .symbols
) throws -> CircuitEquations {
    var circuit = example.circuit
    circuit.simulation.analysis = analysis
    circuit.simulation.integrationMethod = method
    return try CircuitEquations(circuit: circuit, notation: notation)
}

private func strings(_ texts: [MathText]) -> [String] { texts.map(\.description) }

@Suite struct EquationsTests {
    /// RC step example: V1 from `in` to ground, R1 from `in` to `out`, C1 from `out` to ground.
    @Test func rcTransientSymbols() throws {
        let eq = try equations(Examples.rcStep, .transient)
        #expect(strings(eq.unknowns) == ["V(in)", "V(out)", "I(V1)", "I(C1)"])
        #expect(eq.rows.map(\.label) == ["Node in", "Node out", "Voltage Source V1", "Capacitor C1"])
        #expect(strings(eq.rows.map(\.law)) == [
            "I(V1) + (V(in) − V(out))/R1 = 0",
            "(V(out) − V(in))/R1 + I(C1) = 0",
            "V(in) = V1(t)",
            "I(C1) = C1·dV(out)/dt",
        ])
        #expect(eq.rows[2].note == "STEP 0 V→5 V")
        #expect(eq.rows[3].solvedForm?.description == "(2·C1/h)·V(out) − I(C1) = (2·C1/h)·V(out)[n−1] + I(C1)[n−1]")
        #expect(eq.matrix.map(strings) == [
            ["1/R1", "−1/R1", "1", ""],
            ["−1/R1", "1/R1", "", "1"],
            ["1", "", "", ""],
            ["", "2·C1/h", "", "−1"],
        ])
        #expect(strings(eq.rhs) == ["", "", "V1(t)", "(2·C1/h)·V(out)[n−1] + I(C1)[n−1]"])
        #expect(eq.summary == "Transient · trapezoidal rule · time step h = 2.5 µs")
    }

    @Test func rcTransientValues() throws {
        let eq = try equations(Examples.rcStep, .transient, method: .backwardEuler, notation: .values)
        #expect(eq.rows[0].law.description == "I(V1) + (V(in) − V(out))/1 kΩ = 0")
        #expect(eq.rows[3].solvedForm?.description == "400 mS·V(out) − I(C1) = 400 mS·V(out)[n−1]")
        #expect(eq.matrix.map(strings)[0] == ["1m", "−1m", "1", ""])
        #expect(eq.matrix.map(strings)[3] == ["", "400m", "", "−1"])
        #expect(eq.rhs[3].description == "400m·V(out)[n−1]")
    }

    @Test func unknownsAreMarked() throws {
        let law = try equations(Examples.rcStep, .transient).rows[3].solvedForm!
        let unknowns = law.runs.filter { $0.style == .unknown }.map(\.text)
        // Previous-step values are known, so only the current V(out) and I(C1) are unknowns.
        #expect(unknowns == ["V(out)", "I(C1)"])
        #expect(law.runs.contains { $0.style == .lowered && $0.text == "n−1" })
    }

    /// Series RLC: V1 → in, R1 in–N1, L1 N1–out, C1 out–ground.
    @Test func dcShortsInductorsAndOpensCapacitors() throws {
        let eq = try equations(Examples.seriesRLC, .operatingPoint, notation: .values)
        let inductor = try #require(eq.rows.first { $0.label == "Inductor L1" })
        #expect(inductor.law.description == "V(N1) − V(out) = 0")
        #expect(inductor.note == "short circuit at DC")
        let capacitor = try #require(eq.rows.first { $0.label == "Capacitor C1" })
        #expect(capacitor.law.description == "I(C1) = 0")
        #expect(capacitor.note == "open circuit at DC")
        // A step source starts at its initial value.
        #expect(eq.rows.first { $0.label == "Voltage Source V1" }?.law.description == "V(in) = 0 V")
    }

    @Test func acUsesImpedances() throws {
        let symbols = try equations(Examples.parallelRLC, .ac)
        let inductor = try #require(symbols.rows.first { $0.label == "Inductor L1" })
        #expect(inductor.law.description == "V(out) = jω·L1·I(L1)")
        #expect(symbols.matrix[inductor.id][inductor.id].description == "−jω·L1")
        let capacitor = try #require(symbols.rows.first { $0.label == "Capacitor C1" })
        #expect(capacitor.law.description == "I(C1) = jω·C1·V(out)")

        let values = try equations(Examples.parallelRLC, .ac, notation: .values)
        #expect(values.matrix[inductor.id][inductor.id].description == "−jω·1m")
        #expect(values.matrix[capacitor.id][1].description == "jω·1µ")
    }

    @Test func currentSourcesAppearInNodeEquations() throws {
        // I1 from node a down to ground, R1 from a to ground.
        var circuit = Circuit()
        circuit.components = [
            Component(kind: .currentSource, name: "I1", position: GridPoint(0, 2), rotation: 1, value: 1e-3),
            Component(kind: .resistor, name: "R1", position: GridPoint(4, 2), rotation: 1, value: 1e3),
            Component(kind: .netLabel, name: "a", position: GridPoint(0, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 4)),
        ]
        circuit.wires = [Wire(start: GridPoint(0, 0), end: GridPoint(4, 0)), Wire(start: GridPoint(0, 4), end: GridPoint(4, 4))]
        circuit.simulation.analysis = .operatingPoint

        let symbols = try CircuitEquations(circuit: circuit, notation: .symbols)
        #expect(symbols.rows.map(\.law.description) == ["I1 + V(a)/R1 = 0"])
        #expect(strings(symbols.rhs) == ["−I1"])
        let values = try CircuitEquations(circuit: circuit, notation: .values)
        #expect(values.rows.map(\.law.description) == ["1 mA + V(a)/1 kΩ = 0"])
        #expect(strings(values.rhs) == ["−1m"])
    }

    /// Inverting amplifier: V1 → in, R1 in–N1, U1 with + grounded and − on N1, R2 N1–out.
    @Test func opAmpLawAndMatrix() throws {
        let symbols = try equations(Examples.invertingAmplifier, .operatingPoint)
        #expect(strings(symbols.unknowns) == ["V(in)", "V(N1)", "V(out)", "I(V1)", "I(U1)"])
        #expect(symbols.rows.map(\.label) == ["Node in", "Node N1", "Node out", "Voltage Source V1", "Op-Amp U1"])
        // The inputs draw no current, so U1 appears only in the output node's law.
        #expect(symbols.rows[1].law.description == "(V(N1) − V(in))/R1 + (V(N1) − V(out))/R2 = 0")
        #expect(symbols.rows[2].law.description == "I(U1) + (V(out) − V(N1))/R2 = 0")
        #expect(symbols.rows[4].law.description == "V(out) = −A[U1]·V(N1)")
        #expect(strings(symbols.matrix[4]) == ["", "A[U1]", "1", "", ""])
        #expect(strings(symbols.matrix.map { $0[4] }) == ["", "", "1", "", ""])
        #expect(symbols.rhs[4].isEmpty)
        #expect(symbols.notes.contains { $0.hasPrefix("An op-amp's output") })

        let values = try equations(Examples.invertingAmplifier, .operatingPoint, notation: .values)
        #expect(values.rows[4].law.description == "V(out) = −100k·V(N1)")
        #expect(strings(values.matrix[4]) == ["", "100k", "1", "", ""])
    }

    @Test func opAmpLawWithBothInputs() throws {
        // Sallen–Key: + on N2 (after R2), − tied to out.
        let eq = try equations(Examples.sallenKeyLowPass, .ac)
        let row = try #require(eq.rows.first { $0.label == "Op-Amp U1" })
        #expect(row.law.description == "V(out) = A[U1]·(V(N2) − V(out))")
        // A·V(−) and the output's own coefficient share the out column: 1 + A.
        let out = try #require(strings(eq.unknowns).firstIndex(of: "V(out)"))
        #expect(eq.matrix[row.id][out].description == "1 + A[U1]")
    }

    /// Diode clipper: V1 → in, R1 in–out, D1 from out down to ground, D2 from ground up to out.
    @Test func diodeLawsAndTangents() throws {
        let symbols = try equations(Examples.diodeClipper, .operatingPoint)
        #expect(strings(symbols.unknowns) == ["V(in)", "V(out)", "I(V1)", "I(D1)", "I(D2)"])
        #expect(symbols.rows[1].law.description == "(V(out) − V(in))/R1 + I(D1) − I(D2) = 0")
        let d1 = symbols.rows[3], d2 = symbols.rows[4]
        #expect(d1.label == "Diode D1")
        #expect(d1.law.description == "I(D1) = I[S,D1]·(exp(V(out)/(n[D1]·V[T])) − 1)")
        #expect(d1.solvedForm?.description == "G[D1]·V(out) − I(D1) = G[D1]·V(out)[k] − I(D1)[k]")
        #expect(d2.law.description == "I(D2) = I[S,D2]·(exp((−V(out))/(n[D2]·V[T])) − 1)")
        #expect(strings(symbols.matrix[3]) == ["", "G[D1]", "", "−1", ""])
        #expect(strings(symbols.matrix[4]) == ["", "−G[D2]", "", "", "−1"])
        #expect(symbols.rhs[3].description == "G[D1]·V(out)[k] − I(D1)[k]")
        #expect(symbols.notes.contains { $0.hasPrefix("Diodes are not linear") })
        // The previous iterate is known: only V(out) and I(D1) are unknowns in the tangent.
        #expect(d1.solvedForm!.runs.filter { $0.style == .unknown }.map(\.text) == ["V(out)", "I(D1)"])

        // The tangent's slope changes every iteration, so it stays symbolic among values.
        let values = try equations(Examples.diodeClipper, .operatingPoint, notation: .values)
        #expect(values.rows[3].law.description == "I(D1) = 10 fA·(exp(V(out)/25.86 mV) − 1)")
        #expect(strings(values.matrix[3]) == ["", "G[D1]", "", "−1", ""])

        let ac = try equations(Examples.diodeClipper, .ac)
        #expect(ac.rows[3].law.description == "I(D1) = G[D1]·V(out)")
        #expect(ac.rows[3].note == "small-signal, at the DC operating point")
        #expect(ac.rows[3].solvedForm == nil)
        #expect(ac.rhs[3].isEmpty)
    }

    /// Q1 with collector on c, base on b, emitter on e; R1 from e to ground; V1 on c, V2 on b.
    private func bjtCircuit(_ polarity: TransistorParameters.Polarity = .n, earlyVoltage: Double = 0) -> Circuit {
        var parameters = TransistorParameters(polarity: polarity)
        parameters.earlyVoltage = earlyVoltage
        var circuit = Circuit(components: [
            Component(kind: .bjt, name: "Q1", position: GridPoint(2, -10), transistor: parameters),
            Component(kind: .resistor, name: "R1", position: GridPoint(0, 2), rotation: 1, value: 1e3),
            Component(kind: .voltageSource, name: "V1", position: GridPoint(4, 2), value: 5),
            Component(kind: .voltageSource, name: "V2", position: GridPoint(8, 2), value: 1),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 4)),
            Component(kind: .ground, name: "GND", position: GridPoint(4, 4)),
            Component(kind: .ground, name: "GND", position: GridPoint(8, 4)),
            Component(kind: .netLabel, name: "e", position: GridPoint(0, 0)),
            Component(kind: .netLabel, name: "c", position: GridPoint(4, 0)),
            Component(kind: .netLabel, name: "b", position: GridPoint(8, 0)),
        ])
        for (name, pin) in zip(["c", "b", "e"], circuit.components[0].pinPositions) {
            circuit.components.append(Component(kind: .netLabel, name: name, position: pin))
        }
        for index in 1...3 { circuit.components[index].rotation = 1 }
        circuit.simulation.analysis = .operatingPoint
        return circuit
    }

    @Test func bjtLawsAndHybridPiTangent() throws {
        let eq = try CircuitEquations(circuit: bjtCircuit(), notation: .symbols)
        #expect(strings(eq.unknowns) == ["V(c)", "V(b)", "V(e)", "Ic(Q1)", "Ib(Q1)", "I(V1)", "I(V2)"])
        #expect(eq.rows.map(\.label) == [
            "Node c", "Node b", "Node e", "NPN Q1 · collector", "NPN Q1 · base", "Voltage Source V1", "Voltage Source V2",
        ])
        // The emitter current is the collector and base currents, leaving the transistor.
        #expect(eq.rows[2].law.description == "−Ic(Q1) − Ib(Q1) + V(e)/R1 = 0")
        #expect(eq.rows[3].law.description
            == "Ic(Q1) = I[S,Q1]·(exp((V(b) − V(e))/V[T]) − exp((V(b) − V(c))/V[T])) − I[S,Q1]·(exp((V(b) − V(c))/V[T]) − 1)")
        #expect(eq.rows[4].law.description
            == "Ib(Q1) = I[S,Q1]/β[F,Q1]·(exp((V(b) − V(e))/V[T]) − 1) + I[S,Q1]·(exp((V(b) − V(c))/V[T]) − 1)")
        #expect(eq.rows[3].solvedForm?.description == "g[m,Q1]·(V(b) − V(e)) − (g[o,Q1] + g[μ,Q1])·(V(b) − V(c)) − Ic(Q1) = "
            + "g[m,Q1]·(V(b) − V(e))[k] − (g[o,Q1] + g[μ,Q1])·(V(b) − V(c))[k] − Ic(Q1)[k]")
        #expect(strings(eq.matrix[3]) == ["g[o,Q1] + g[μ,Q1]", "g[m,Q1] − g[o,Q1] − g[μ,Q1]", "−g[m,Q1]", "−1", "", "", ""])
        #expect(strings(eq.matrix[4]) == ["−g[μ,Q1]", "g[π,Q1] + g[μ,Q1]", "−g[π,Q1]", "", "−1", "", ""])
        #expect(eq.notes.contains { $0.hasPrefix("Transistors are not linear") })
        #expect(eq.notes.contains { $0.hasPrefix("BJTs follow the Ebers–Moll model") })

        let values = try CircuitEquations(circuit: bjtCircuit(earlyVoltage: 50), notation: .values)
        #expect(values.rows[4].law.description
            == "Ib(Q1) = 10 fA/100·(exp((V(b) − V(e))/25.86 mV) − 1) + 10 fA·(exp((V(b) − V(c))/25.86 mV) − 1)")
        #expect(values.rows[3].law.description.hasSuffix("·(1 − (V(b) − V(c))/50 V) − 10 fA·(exp((V(b) − V(c))/25.86 mV) − 1)"))

        // PNP: the NPN laws with voltages and currents negated.
        let pnp = try CircuitEquations(circuit: bjtCircuit(.p), notation: .symbols)
        #expect(pnp.rows[3].label == "PNP Q1 · collector")
        #expect(pnp.rows[3].law.description
            == "Ic(Q1) = −I[S,Q1]·(exp((V(e) − V(b))/V[T]) − exp((V(c) − V(b))/V[T])) + I[S,Q1]·(exp((V(c) − V(b))/V[T]) − 1)")

        var ac = bjtCircuit()
        ac.simulation.analysis = .ac
        let small = try CircuitEquations(circuit: ac, notation: .symbols)
        #expect(small.rows[4].law.description == "Ib(Q1) = g[π,Q1]·(V(b) − V(e)) + g[μ,Q1]·(V(b) − V(c))")
        #expect(small.rhs[3].isEmpty)
    }

    @Test func mosfetSaturationLaw() throws {
        var parameters = TransistorParameters()
        parameters.channelLengthModulation = 0.02
        var circuit = Circuit(components: [
            Component(kind: .mosfet, name: "M1", position: GridPoint(2, -10), transistor: parameters),
            Component(kind: .ground, name: "GND", position: GridPoint(3, -8)),
            Component(kind: .netLabel, name: "d", position: GridPoint(3, -12)),
            Component(kind: .netLabel, name: "g", position: GridPoint(0, -10)),
            Component(kind: .voltageSource, name: "V1", position: GridPoint(0, 2), rotation: 1, value: 2),
            Component(kind: .netLabel, name: "g", position: GridPoint(0, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 4)),
            Component(kind: .voltageSource, name: "V2", position: GridPoint(4, 2), rotation: 1, value: 5),
            Component(kind: .netLabel, name: "d", position: GridPoint(4, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(4, 4)),
        ])
        circuit.simulation.analysis = .operatingPoint
        let symbols = try CircuitEquations(circuit: circuit, notation: .symbols)
        let m1 = try #require(symbols.rows.first { $0.label == "NMOS M1" })
        #expect(m1.law.description == "Id(M1) = ½·k[M1]·(V(g) − V[th,M1])²·(1 + λ[M1]·V(d))")
        #expect(m1.note == "in saturation; see the notes for the other regions")
        #expect(m1.solvedForm?.description == "g[m,M1]·V(g) + g[ds,M1]·V(d) − Id(M1) = g[m,M1]·V(g)[k] + g[ds,M1]·V(d)[k] − Id(M1)[k]")
        let values = try CircuitEquations(circuit: circuit, notation: .values)
        #expect(values.rows.first { $0.label == "NMOS M1" }?.law.description == "Id(M1) = 1 mA/V²·(V(g) − 1 V)²·(1 + 20m·V(d))")

        circuit.components[0].transistor?.polarity = .p
        let pmos = try CircuitEquations(circuit: circuit, notation: .symbols)
        // Upside down: the drain pin is now at the bottom (on ground) and the source on top (on d).
        #expect(pmos.rows.first { $0.label == "PMOS M1" }?.law.description
            == "Id(M1) = −½·k[M1]·(V(d) − V(g) − V[th,M1])²·(1 + λ[M1]·V(d))")
    }

    /// The displayed matrix must be the one the simulator factors, apart from gmin.
    @Test(arguments: Examples.all.map(\.name))
    func matrixMatchesSimulator(name: String) throws {
        let example = Examples.all.first { $0.name == name }!
        let netlist = try Netlist(circuit: example.circuit)
        let layout = Simulator.Layout(netlist)
        let nodeRows = netlist.nodeCount - 1

        func expectMatch(_ eq: CircuitEquations, _ expected: (Int, Int) -> Complex, omega: Double = 0) {
            #expect(eq.size == layout.size)
            #expect(eq.rows.map(\.id) == Array(0..<eq.size), "rows are in matrix order")
            for r in 0..<layout.size {
                for c in 0..<layout.size {
                    let gmin = r == c && r < nodeRows ? Simulator.gmin : 0
                    let want = expected(r, c), got = eq.coefficients[r][c]
                    #expect(abs(got.real - (want.re - gmin)) <= 1e-9 * max(1, abs(want.re)), "\(name) A[\(r),\(c)]")
                    #expect(abs(omega * got.reactive - want.im) <= 1e-9 * max(1, abs(want.im)), "\(name) A[\(r),\(c)]")
                }
            }
        }

        var settings = example.circuit.simulation
        settings.analysis = .operatingPoint
        let dc = Simulator.assembleMatrix(netlist, layout: layout, mode: .dc)
        expectMatch(CircuitEquations(netlist: netlist, settings: settings, notation: .symbols)) { Complex(dc[$0, $1]) }

        settings.analysis = .transient
        let h = try Simulator.timeSteps(settings).h
        for (method, mode) in [(SimulationSettings.IntegrationMethod.trapezoidal, Simulator.Mode.trapezoidal(h: h)), (.backwardEuler, .backwardEuler(h: h))] {
            settings.integrationMethod = method
            let matrix = Simulator.assembleMatrix(netlist, layout: layout, mode: mode)
            expectMatch(CircuitEquations(netlist: netlist, settings: settings, notation: .symbols)) { Complex(matrix[$0, $1]) }
        }

        settings.analysis = .ac
        let omega = 2 * Double.pi * 1234
        // Diode and transistor slopes depend on the solution; `coefficients` leaves them out, and so does this matrix.
        let ac = Simulator.assembleAC(netlist, layout: layout, omega: omega, slopes: [:]).matrix
        expectMatch(CircuitEquations(netlist: netlist, settings: settings, notation: .symbols), { ac[$0, $1] }, omega: omega)
    }

    @Test func reportsNetlistErrors() {
        #expect(throws: NetlistError.empty) { try CircuitEquations(circuit: Circuit(), notation: .symbols) }
    }
}
