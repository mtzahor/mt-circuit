import Foundation

// MARK: - Math text

/// Equation text with typesetting hints, so the app can highlight unknowns and lower subscripts.
public struct MathText: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public enum Style: Hashable, Sendable {
        case plain
        /// A quantity the simulator solves for, such as V(out) or I(C1).
        case unknown
        /// A subscript, as in V(out)ₙ₋₁.
        case lowered
    }

    public struct Run: Hashable, Sendable {
        public var text: String
        public var style: Style
    }

    public private(set) var runs: [Run] = []

    public init(_ text: String = "", style: Style = .plain) {
        if !text.isEmpty { runs = [Run(text: text, style: style)] }
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var isEmpty: Bool { runs.isEmpty }

    /// Plain text, with subscripts in brackets: "V(out)[n−1]".
    public var description: String {
        runs.map { $0.style == .lowered ? "[\($0.text)]" : $0.text }.joined()
    }

    public static func + (lhs: MathText, rhs: MathText) -> MathText {
        var result = lhs
        for run in rhs.runs {
            if let last = result.runs.indices.last, result.runs[last].style == run.style {
                result.runs[last].text += run.text
            } else {
                result.runs.append(run)
            }
        }
        return result
    }
}

/// A term with its sign kept apart, so sums read "a − b" rather than "a + −b".
struct SignedText {
    var negative = false
    var text: MathText

    var signed: MathText { negative ? "−" + text : text }

    /// Terms joined as "a + b − c"; "0" when there are none.
    static func sum(_ terms: [SignedText]) -> MathText {
        guard let first = terms.first else { return "0" }
        return terms.dropFirst().reduce(first.signed) { result, term in
            result + MathText(term.negative ? " − " : " + ") + term.text
        }
    }
}

// MARK: - Circuit equations

/// The equations the simulator solves, written out to read: Kirchhoff's current law at every
/// node, the law of every voltage source, inductor, capacitor, diode, transistor current, op-amp,
/// and logic gate, and the resulting Modified Nodal Analysis system A·x = b.
///
/// Rows and unknowns are in the simulator's order (node voltages, then branch currents), and the
/// matrix has exactly the simulator's coefficients, except for the tiny `gmin` conductances. Diodes,
/// transistors, and logic gates are shown by their tangents, whose slopes change from one Newton
/// iteration to the next.
public struct CircuitEquations: Sendable {
    public enum Notation: String, CaseIterable, Sendable {
        /// Component names stand for their values: "(V(in) − V(out))/R1".
        case symbols
        /// Values substituted: "(V(in) − V(out))/1 kΩ".
        case values

        public var displayName: String {
            switch self {
            case .symbols: "Symbols"
            case .values: "Values"
            }
        }
    }

    public struct Row: Identifiable, Sendable {
        /// Index of the row in the matrix.
        public var id: Int
        /// "Node out", "Capacitor C1", "Op-Amp U1", "NPN Q1 · collector", or "NAND Gate U2".
        public var label: String
        /// The node whose currents the row balances; nil for an element's row.
        public var node: Int?
        /// Kirchhoff's current law at the node, or the element's law.
        public var law: MathText
        /// The law in the form actually solved: discretized in time for a transient step, or
        /// the tangent of a diode, transistor, or logic gate current for a Newton iteration.
        public var solvedForm: MathText?
        /// A short remark, such as "open circuit at DC" or a source's waveform.
        public var note: String?
    }

    /// The analysis in one line, e.g. "Transient · trapezoidal rule · h = 5 µs".
    public var summary: String
    public var unknowns: [MathText]
    public var rows: [Row]
    /// `matrix[row][column]` of A; empty text is a zero.
    public var matrix: [[MathText]]
    /// The right-hand side b; empty text is a zero.
    public var rhs: [MathText]
    /// Conventions and simplifications to know when reading the equations.
    public var notes: [String]
    /// Value of every matrix entry, leaving out the slopes of diodes, transistors, and logic gates,
    /// which the simulator adds while solving.
    var coefficients: [[Coefficient]]

    public var size: Int { unknowns.count }

    public init(circuit: Circuit, notation: Notation) throws {
        self.init(netlist: try Netlist(circuit: circuit), settings: circuit.simulation, notation: notation)
    }

    public init(netlist: Netlist, settings: SimulationSettings, notation: Notation) {
        let builder = EquationBuilder(netlist: netlist, settings: settings, notation: notation)
        let layout = builder.layout
        let nodes = 1..<max(1, netlist.nodeCount)
        let branches = netlist.elements.indices.filter { layout.branch[$0] != nil }

        unknowns = nodes.map { builder.voltage($0) } + branches.flatMap { index in
            (0..<netlist.elements[index].branchCount).map { builder.current(netlist.elements[index], branch: $0) }
        }
        rows = nodes.map { node in
            Row(id: node - 1, label: "Node \(netlist.nodeNames[node])", node: node, law: builder.nodeLaw(node))
        }
        for index in branches {
            let element = netlist.elements[index]
            for branch in 0..<element.branchCount {
                let law = builder.elementLaw(element, branch: branch)
                rows.append(Row(
                    id: layout.branch[index]! + branch, label: builder.label(element, branch: branch),
                    law: law.law, solvedForm: law.solved, note: law.note))
            }
        }

        let (a, b) = builder.assemble()
        matrix = a.map { $0.map(builder.render) }
        rhs = b.map(builder.render)
        coefficients = a.map { $0.map { EquationBuilder.value($0.filter { $0.factor.isEmpty }) } }
        summary = builder.summary
        notes = builder.notes
    }
}

/// A matrix coefficient `real + jω·reactive`; only AC analysis has reactive parts.
struct Coefficient: Hashable, Sendable {
    var real = 0.0
    var reactive = 0.0
}

// MARK: - Builder

private struct EquationBuilder {
    enum Domain {
        case dc
        /// Integration method and time step h.
        case transient(SimulationSettings.IntegrationMethod, Double)
        case ac
    }

    /// One term of a matrix entry or right-hand side: ± coefficient · factor.
    struct Term {
        var negative = false
        /// The coefficient as a formula, such as "1/R1" or "2·C1/h"; empty means 1.
        var symbol = MathText()
        var value = 1.0
        /// Whether the coefficient is multiplied by jω.
        var reactive = false
        /// A known quantity the coefficient multiplies, such as I(L1)ₙ₋₁ or V1(t); empty for a plain number.
        var factor = MathText()

        var negated: Term {
            var term = self
            term.negative.toggle()
            return term
        }
    }

    let netlist: Netlist
    let settings: SimulationSettings
    let notation: CircuitEquations.Notation
    let layout: Simulator.Layout
    let domain: Domain

    init(netlist: Netlist, settings: SimulationSettings, notation: CircuitEquations.Notation) {
        self.netlist = netlist
        self.settings = settings
        self.notation = notation
        layout = Simulator.Layout(netlist)
        switch settings.analysis {
        case .operatingPoint:
            domain = .dc
        case .transient:
            domain = .transient(settings.integrationMethod, (try? Simulator.timeSteps(settings))?.h ?? .nan)
        case .ac:
            domain = .ac
        }
    }

    // MARK: Names

    func voltage(_ node: Int, style: MathText.Style = .unknown) -> MathText {
        MathText("V(\(netlist.nodeNames[node]))", style: style)
    }

    /// One of the element's currents (see `NetlistElement.currentNames`): I(R1), or Ib(Q1) for branch 1 of a BJT.
    func current(_ element: NetlistElement, branch: Int = 0, style: MathText.Style = .unknown) -> MathText {
        MathText(element.currentNames[branch], style: style)
    }

    /// "Capacitor C1", "NPN Q1 · collector", "PMOS M2", "NAND Gate U1": the label of an element's row.
    func label(_ element: NetlistElement, branch: Int) -> String {
        let n = element.transistor.polarity == .n
        switch element.kind {
        case .bjt: return "\(n ? "NPN" : "PNP") \(element.name) · \(branch == 0 ? "collector" : "base")"
        case .mosfet: return "\(n ? "NMOS" : "PMOS") \(element.name)"
        case .logicGate: return "\(element.logic.function.displayName) Gate \(element.name)"
        default: return "\(element.kind.displayName) \(element.name)"
        }
    }

    /// V(p) − V(n), leaving out ground.
    func difference(_ p: Int, _ n: Int, style: MathText.Style = .unknown) -> MathText {
        if n == 0 { return voltage(p, style: style) }
        if p == 0 { return "−" + voltage(n, style: style) }
        return voltage(p, style: style) + " − " + voltage(n, style: style)
    }

    /// `difference`, ready to be multiplied: in parentheses unless it is a single node voltage.
    func differenceFactor(_ p: Int, _ n: Int, style: MathText.Style = .unknown) -> MathText {
        n == 0 ? difference(p, n, style: style) : "(" + difference(p, n, style: style) + ")"
    }

    /// Voltage across the element, V(a) − V(b), leaving out ground.
    func across(_ element: NetlistElement, style: MathText.Style = .unknown) -> MathText {
        difference(element.nodeA, element.nodeB, style: style)
    }

    /// `across`, ready to be multiplied: in parentheses unless it is a single node voltage.
    func acrossFactor(_ element: NetlistElement, style: MathText.Style = .unknown) -> MathText {
        differenceFactor(element.nodeA, element.nodeB, style: style)
    }

    /// Control voltage `j` of a nonlinear element (see `NetlistElement.controlNodes`), ready to be multiplied.
    func controlFactor(_ element: NetlistElement, _ j: Int, style: MathText.Style = .unknown) -> MathText {
        let nodes = element.controlNodes[j]
        return differenceFactor(nodes.0, nodes.1, style: style)
    }

    /// The value of `quantity` at the previous time step.
    func previous(_ quantity: MathText) -> MathText {
        quantity + MathText("n−1", style: .lowered)
    }

    /// The value of `quantity` at the previous Newton iteration.
    func iterate(_ quantity: MathText) -> MathText {
        quantity + MathText("k", style: .lowered)
    }

    /// A symbol with the element's name as subscript, such as G with subscript D1, or I with subscript S,D1.
    func subscripted(_ symbol: String, _ element: NetlistElement, prefix: String = "") -> MathText {
        MathText(symbol) + MathText(prefix + element.name, style: .lowered)
    }

    /// A logic gate's output resistance, R_out or its value.
    var outputResistance: MathText {
        switch notation {
        case .symbols: "R" + MathText("out", style: .lowered)
        case .values: Self.quantity(LogicGateModel.outputResistance, unit: "Ω")
        }
    }

    /// The thermal voltage, Vt or its value.
    var thermalVoltage: MathText {
        switch notation {
        case .symbols: "V" + MathText("T", style: .lowered)
        case .values: Self.quantity(DiodeModel.thermalVoltage, unit: "V")
        }
    }

    /// A device parameter in a law: its symbol with `role` and the element's name as subscript
    /// (I with subscript S,Q1), or its value.
    func deviceParameter(_ symbol: String, _ role: String, _ element: NetlistElement, value: Double, unit: String) -> MathText {
        switch notation {
        case .symbols: subscripted(symbol, element, prefix: role.isEmpty ? "" : role + ",")
        case .values: unit.isEmpty ? Self.number(value) : Self.quantity(value, unit: unit)
        }
    }

    // MARK: Numbers

    /// A matrix number, with an SI prefix and no unit: "1m", "400m", "2k".
    static func number(_ value: Double) -> MathText {
        MathText(minusSign(SIFormat.compact(value)))
    }

    /// A value with its unit: "1 kΩ", "400 mS".
    static func quantity(_ value: Double, unit: String) -> MathText {
        MathText(minusSign(SIFormat.string(value, unit: unit, significantDigits: 4)))
    }

    static func minusSign(_ text: String) -> String {
        text.replacingOccurrences(of: "-", with: "−")
    }

    /// A component's value: its name ("R1"), or the value with its unit ("1 kΩ").
    /// An op-amp's open-loop gain is A with its name as subscript, or a plain number.
    func parameter(_ element: NetlistElement) -> MathText {
        switch (notation, element.kind) {
        case (.symbols, .opAmp): gain(element).symbol
        case (.symbols, _): MathText(element.name)
        case (.values, .opAmp): Self.number(element.value)
        case (.values, _): Self.quantity(element.value, unit: element.kind.unitSymbol)
        }
    }

    /// An op-amp's open-loop gain as a matrix coefficient: A with its name as subscript.
    func gain(_ element: NetlistElement) -> Term {
        Term(symbol: "A" + MathText(element.name, style: .lowered), value: element.value)
    }

    /// The companion-model coefficient: C/h or L/h for backward Euler, 2C/h or 2L/h for the trapezoidal rule.
    func stepCoefficient(_ element: NetlistElement, method: SimulationSettings.IntegrationMethod, h: Double) -> Term {
        let trapezoidal = method == .trapezoidal
        return Term(
            symbol: MathText(trapezoidal ? "2·\(element.name)/h" : "\(element.name)/h"),
            value: (trapezoidal ? 2 : 1) * element.value / h)
    }

    /// `stepCoefficient` as a multiplier in a law: "(2·C1/h)·" or "400 mS·".
    func stepMultiplier(_ element: NetlistElement, method: SimulationSettings.IntegrationMethod, h: Double) -> MathText {
        let term = stepCoefficient(element, method: method, h: h)
        switch notation {
        case .symbols: return "(" + term.symbol + ")·"
        case .values: return Self.quantity(term.value, unit: element.kind == .capacitor ? "S" : "Ω") + "·"
        }
    }

    // MARK: Sources

    /// A source's value: a number at DC and for constant sources, a function of time in transient
    /// analysis, a phasor in AC analysis. `unit` is used for phasors written out as values.
    func sourceTerm(_ element: NetlistElement, unit: String = "") -> Term {
        let waveform = element.waveform
        switch domain {
        case .dc:
            let symbol = waveform.shape == .dc ? element.name : "\(element.name)(0)"
            return Term(symbol: MathText(symbol), value: waveform.value(at: 0, level: element.value))
        case .transient:
            guard waveform.shape != .dc else { return Term(symbol: MathText(element.name), value: element.value) }
            return Term(factor: MathText("\(element.name)(t)"))
        case .ac:
            guard notation == .values, waveform.acPhase != 0 else {
                return Term(symbol: MathText(element.name), value: waveform.acMagnitude)
            }
            let magnitude = unit.isEmpty
                ? SIFormat.compact(waveform.acMagnitude)
                : SIFormat.string(waveform.acMagnitude, unit: unit, significantDigits: 4)
            return Term(factor: MathText(Self.minusSign("\(magnitude)∠\(String(format: "%g", waveform.acPhase))°")))
        }
    }

    /// A source's value in a law, with its unit when values are shown.
    func sourceValue(_ element: NetlistElement) -> SignedText {
        let unit = element.kind.unitSymbol
        let term = sourceTerm(element, unit: unit)
        if !term.factor.isEmpty { return SignedText(text: term.factor) }
        switch notation {
        case .symbols: return SignedText(text: term.symbol)
        case .values: return SignedText(negative: term.value < 0, text: Self.quantity(abs(term.value), unit: unit))
        }
    }

    /// The waveform of a time-varying source in transient analysis, e.g. "STEP 0 V→5 V".
    func sourceNote(_ element: NetlistElement) -> String? {
        guard case .transient = domain, element.waveform.shape != .dc else { return nil }
        return element.waveform.summary(level: element.value, unit: element.kind.unitSymbol)
    }

    // MARK: Laws

    /// Kirchhoff's current law: the currents leaving `node` sum to zero.
    func nodeLaw(_ node: Int) -> MathText {
        var terms: [SignedText] = []
        for element in netlist.elements where element.nodes.contains(node) {
            // Element currents flow from pin 1 (node A) to pin 2 inside the element, so they leave node A.
            let leaving = element.nodeA == node
            switch element.kind {
            case .resistor:
                let other = leaving ? element.nodeB : element.nodeA
                let drop = other == 0 ? voltage(node) : "(" + voltage(node) + " − " + voltage(other) + ")"
                terms.append(SignedText(text: drop + "/" + parameter(element)))
            case .currentSource:
                let source = sourceValue(element)
                terms.append(SignedText(negative: !leaving != source.negative, text: source.text))
            case .ground, .netLabel:
                break
            default:
                // Branch currents leave the node they flow from, such as an op-amp's output, a BJT's
                // collector and base, or a MOSFET's drain, and enter the node they flow to.
                for (branch, nodes) in element.branchNodes.enumerated() {
                    if nodes.from == node { terms.append(SignedText(text: current(element, branch: branch))) }
                    if nodes.to == node { terms.append(SignedText(negative: true, text: current(element, branch: branch))) }
                }
            }
        }
        return SignedText.sum(terms) + " = 0"
    }

    /// The law of a voltage source, inductor, capacitor, diode, op-amp, transistor current
    /// (`branch` 1 is a BJT's base current), or logic gate, and the form solved: discretized in time
    /// in transient analysis, or the tangent of a nonlinear current.
    func elementLaw(_ element: NetlistElement, branch: Int) -> (law: MathText, solved: MathText?, note: String?) {
        switch (element.kind, domain) {
        case (.diode, .ac), (.bjt, .ac), (.mosfet, .ac), (.logicGate, .ac):
            let law = current(element, branch: branch) + " = " + SignedText.sum(tangentTerms(element, branch: branch) {
                controlFactor(element, $0)
            })
            return (law, nil, "small-signal, at the DC operating point")
        case (.diode, _), (.bjt, _), (.mosfet, _), (.logicGate, _):
            let (law, note) = nonlinearLaw(element, branch: branch)
            let current = current(element, branch: branch)
            let tangent = SignedText.sum(tangentTerms(element, branch: branch) { controlFactor(element, $0) }
                + [SignedText(negative: true, text: current)])
            let previous = SignedText.sum(tangentTerms(element, branch: branch) { iterate(controlFactor(element, $0, style: .plain)) }
                + [SignedText(negative: true, text: iterate(self.current(element, branch: branch, style: .plain)))])
            return (current + " = " + law, tangent + " = " + previous, note)
        case (.voltageSource, _):
            return (across(element) + " = " + sourceValue(element).signed, nil, sourceNote(element))
        case (.opAmp, _):
            let output = element.outputNode == 0 ? "0" : voltage(element.outputNode)
            // With the + input grounded: "−A·V(−)" rather than "A·(−V(−))".
            let gain = element.nodeA == 0
                ? "−" + parameter(element) + "·" + voltage(element.nodeB)
                : parameter(element) + "·" + acrossFactor(element)
            return (output + " = " + gain, nil, nil)
        case (.inductor, .dc):
            return (across(element) + " = 0", nil, "short circuit at DC")
        case (.capacitor, .dc):
            return (current(element) + " = 0", nil, "open circuit at DC")
        case let (.inductor, .transient(method, h)):
            let k = stepMultiplier(element, method: method, h: h)
            var rhs = "−" + k + previous(current(element, style: .plain))
            if method == .trapezoidal { rhs = rhs + " − " + previous(acrossFactor(element, style: .plain)) }
            let law = across(element) + " = " + parameter(element) + "·d" + current(element) + "/dt"
            return (law, across(element) + " − " + k + current(element) + " = " + rhs, nil)
        case let (.capacitor, .transient(method, h)):
            let k = stepMultiplier(element, method: method, h: h)
            var rhs = k + previous(acrossFactor(element, style: .plain))
            if method == .trapezoidal { rhs = rhs + " + " + previous(current(element, style: .plain)) }
            let law = current(element) + " = " + parameter(element) + "·d" + acrossFactor(element) + "/dt"
            return (law, k + acrossFactor(element) + " − " + current(element) + " = " + rhs, nil)
        case (.inductor, .ac):
            return (across(element) + " = jω·" + parameter(element) + "·" + current(element), nil, nil)
        case (.capacitor, .ac):
            return (current(element) + " = jω·" + parameter(element) + "·" + acrossFactor(element), nil, nil)
        default:
            return (MathText(), nil, nil)
        }
    }

    // MARK: Nonlinear elements

    /// The right side of a diode's, transistor current's, or logic gate's exact law, and a remark on it.
    func nonlinearLaw(_ element: NetlistElement, branch: Int) -> (law: MathText, note: String?) {
        if element.kind == .logicGate { return gateLaw(element) }
        // A P-type transistor's laws are the N-type ones with voltages and currents negated:
        // its controls read V_EB, V_CB, V_SG, V_SD, and its current takes a minus sign.
        let flip = element.kind != .diode && element.transistor.polarity == .p
        func control(_ j: Int) -> MathText {
            let nodes = element.controlNodes[j]
            return flip ? differenceFactor(nodes.1, nodes.0) : differenceFactor(nodes.0, nodes.1)
        }
        func signed(_ terms: [SignedText]) -> MathText {
            SignedText.sum(flip ? terms.map { SignedText(negative: !$0.negative, text: $0.text) } : terms)
        }
        let vt = thermalVoltage
        switch element.kind {
        case .diode:
            let saturation = deviceParameter("I", "S", element, value: element.value, unit: "A")
            let slope = notation == .values
                ? Self.quantity(element.diode.slopeVoltage, unit: "V")
                : "(" + subscripted("n", element) + "·" + vt + ")"
            return (saturation + "·(exp(" + control(0) + "/" + slope + ") − 1)", nil)
        case .bjt:
            let parameters = element.transistor
            let saturation = deviceParameter("I", "S", element, value: parameters.saturationCurrent, unit: "A")
            let forward = "exp(" + control(0) + "/" + vt + ")", reverse = "exp(" + control(1) + "/" + vt + ")"
            if branch == 1 {
                let beta = deviceParameter("β", "F", element, value: element.value, unit: "")
                return (signed([
                    SignedText(text: saturation + "/" + beta + "·(" + forward + " − 1)"),
                    SignedText(text: saturation + "·(" + reverse + " − 1)"),
                ]), nil)
            }
            var transport = saturation + "·(" + forward + " − " + reverse + ")"
            if parameters.earlyVoltage > 0 {
                let early = deviceParameter("V", "A", element, value: parameters.earlyVoltage, unit: "V")
                transport = transport + "·(1 − " + control(1) + "/" + early + ")"
            }
            return (signed([SignedText(text: transport), SignedText(negative: true, text: saturation + "·(" + reverse + " − 1)")]), nil)
        default:
            let parameters = element.transistor
            let nodes = element.controlNodes[0]
            let gateSource = flip ? difference(nodes.1, nodes.0) : difference(nodes.0, nodes.1)
            let threshold = deviceParameter("V", "th", element, value: element.value, unit: "V")
            let halfK = notation == .values
                ? Self.quantity(parameters.transconductance / 2, unit: "A/V²")
                : "½·" + subscripted("k", element)
            var law = halfK + "·(" + gateSource + " − " + threshold + ")²"
            if parameters.channelLengthModulation > 0 {
                let lambda = deviceParameter("λ", "", element, value: parameters.channelLengthModulation, unit: "")
                law = law + "·(1 + " + lambda + "·" + control(1) + ")"
            }
            return (signed([SignedText(text: law)]), "in saturation; see the notes for the other regions")
        }
    }

    /// A logic gate's output current, (V(out) − V_DD·f(inputs))/R_out. In a transient analysis,
    /// f takes the inputs one propagation delay earlier.
    func gateLaw(_ element: NetlistElement) -> (law: MathText, note: String?) {
        let gate = element.gate
        let delayed: Bool = if case .transient = domain { gate.delay > 0 } else { false }
        let delay = deviceParameter("t", "pd", element, value: gate.delay, unit: "s")
        let inputs = element.inputNodes.map { node -> MathText in
            guard node != 0 else { return "0" }
            return delayed ? voltage(node, style: .plain) + "(t − " + delay + ")" : voltage(node)
        }
        let arguments = inputs.dropFirst().reduce(inputs[0]) { $0 + ", " + $1 }
        let supply = deviceParameter("V", "DD", element, value: gate.supply, unit: "V")
        let target = supply + "·" + MathText(gate.function.displayName) + "(" + arguments + ")"
        let output = element.outputNode == 0 ? MathText("0") : voltage(element.outputNode)
        return ("(" + output + " − " + target + ")/" + outputResistance,
                delayed ? "inputs one propagation delay earlier" : nil)
    }

    /// The slopes of a nonlinear element's tangent as symbols: `slopes[i][j]` are the terms of
    /// ∂I_i/∂V_j, in `NonlinearModel` order. A BJT's are its hybrid-π parameters. A logic gate's
    /// first slope is its output conductance G_out = 1/R_out, a constant; in an AC sweep its inputs'
    /// slopes are delayed by its propagation delay.
    func slopeTerms(_ element: NetlistElement) -> [[[Term]]] {
        func g(_ name: String) -> Term {
            Term(factor: "g" + MathText("\(name),\(element.name)", style: .lowered))
        }
        switch element.kind {
        case .logicGate:
            let conductance: MathText = notation == .values
                ? Self.number(1 / LogicGateModel.outputResistance)
                : "G" + MathText("out", style: .lowered)
            let lagged: Bool = if case .ac = domain { element.gate.delay > 0 } else { false }
            let inputs = ["A", "B"].prefix(element.inputNodes.count).map { input -> [Term] in
                let slope = g(input).factor
                guard lagged else { return [Term(factor: slope)] }
                let delay = deviceParameter("t", "pd", element, value: element.gate.delay, unit: "s")
                return [Term(factor: "(" + slope + "·e^(−jω·" + delay + "))")]
            }
            return [[[Term(factor: conductance)]] + inputs]
        case .diode:
            // The tangent's slope is not a fixed number, so it stays a symbol even when values are shown.
            return [[[Term(factor: subscripted("G", element))]]]
        case .bjt:
            // ∂Ic/∂V_BE = g_m, ∂Ic/∂V_BC = −(g_o + g_μ), ∂Ib/∂V_BE = g_π, ∂Ib/∂V_BC = g_μ.
            return [[[g("m")], [g("o").negated, g("μ").negated]], [[g("π")], [g("μ")]]]
        default:
            return [[[g("m")], [g("ds")]]]
        }
    }

    /// The terms of one slope as a single signed coefficient: "g_m", or "−(g_o + g_μ)".
    func coefficient(_ terms: [Term]) -> SignedText {
        if terms.count == 1 { return SignedText(negative: terms[0].negative, text: terms[0].factor) }
        let negative = terms.allSatisfy(\.negative)
        let inner = SignedText.sum(terms.map { SignedText(negative: $0.negative != negative, text: $0.factor) })
        return SignedText(negative: negative, text: "(" + inner + ")")
    }

    /// Σⱼ slope·control for one current of a nonlinear element, each control written by `control`.
    func tangentTerms(_ element: NetlistElement, branch: Int, control: (Int) -> MathText) -> [SignedText] {
        slopeTerms(element)[branch].enumerated().map { j, terms in
            let c = coefficient(terms)
            return SignedText(negative: c.negative, text: c.text + "·" + control(j))
        }
    }

    // MARK: Matrix

    /// The terms of every entry of A and b, stamped like `Simulator.assembleMatrix` (without gmin).
    func assemble() -> (matrix: [[[Term]]], rhs: [[Term]]) {
        let size = layout.size
        var matrix = Array(repeating: Array(repeating: [Term](), count: size), count: size)
        var rhs = Array(repeating: [Term](), count: size)
        func add(_ row: Int?, _ column: Int?, _ term: Term) {
            guard let row, let column else { return }
            matrix[row][column].append(term)
        }

        for (index, element) in netlist.elements.enumerated() {
            let a = layout.row(element.nodeA), b = layout.row(element.nodeB)
            switch element.kind {
            case .resistor:
                let g = Term(symbol: "1/" + MathText(element.name), value: 1 / element.value)
                add(a, a, g)
                add(b, b, g)
                add(a, b, g.negated)
                add(b, a, g.negated)
            case .currentSource:
                let source = sourceTerm(element)
                if let a { rhs[a].append(source.negated) }
                if let b { rhs[b].append(source) }
            case .diode, .bjt, .mosfet, .logicGate:
                // As `stampNonlinear`, with the tangent's slopes and its offset at the previous iterate.
                let first = layout.branch[index]!
                let slopes = slopeTerms(element)
                for (branch, nodes) in element.branchNodes.enumerated() {
                    let k = first + branch
                    add(layout.row(nodes.from), k, Term())
                    add(layout.row(nodes.to), k, Term(negative: true))
                    add(k, k, Term(negative: true))
                    for (j, control) in element.controlNodes.enumerated() {
                        for term in slopes[branch][j] {
                            add(k, layout.row(control.0), term)
                            add(k, layout.row(control.1), term.negated)
                        }
                    }
                    if case .ac = domain { continue }
                    rhs[k] = tangentTerms(element, branch: branch) { iterate(controlFactor(element, $0, style: .plain)) }
                        .map { Term(negative: $0.negative, factor: $0.text) }
                        + [Term(negative: true, factor: iterate(current(element, branch: branch, style: .plain)))]
                }
            case .voltageSource, .inductor, .capacitor:
                let k = layout.branch[index]!
                let (cv, ci) = branchCoefficients(element)
                add(a, k, Term())
                add(b, k, Term(negative: true))
                if let cv {
                    add(k, a, cv)
                    add(k, b, cv.negated)
                }
                if let ci { add(k, k, ci) }
                rhs[k] = branchRHS(element)
            case .opAmp:
                // As `stampOpAmp`: vout − A·(v+ − v−) = 0, with the output current entering the output node's law.
                let k = layout.branch[index]!, out = layout.row(element.outputNode)
                add(out, k, Term())
                add(k, out, Term())
                add(k, a, gain(element).negated)
                add(k, b, gain(element))
            case .ground, .netLabel:
                break
            }
        }
        return (matrix, rhs)
    }

    /// Coefficients of the branch equation cv·(va − vb) + ci·i = rhs, as in `Simulator.branchEquation`; nil is zero.
    func branchCoefficients(_ element: NetlistElement) -> (cv: Term?, ci: Term?) {
        switch (element.kind, domain) {
        case (.voltageSource, _), (.inductor, .dc):
            return (Term(), nil)
        case (.capacitor, .dc):
            return (nil, Term())
        case let (.inductor, .transient(method, h)):
            return (Term(), stepCoefficient(element, method: method, h: h).negated)
        case let (.capacitor, .transient(method, h)):
            return (stepCoefficient(element, method: method, h: h), Term(negative: true))
        case (.inductor, .ac):
            return (Term(), Term(negative: true, symbol: MathText(element.name), value: element.value, reactive: true))
        case (.capacitor, .ac):
            return (Term(symbol: MathText(element.name), value: element.value, reactive: true), Term(negative: true))
        default:
            return (nil, nil)
        }
    }

    /// Right-hand side of a branch equation: the source's value, or the state at the previous step.
    func branchRHS(_ element: NetlistElement) -> [Term] {
        switch (element.kind, domain) {
        case (.voltageSource, _):
            return [sourceTerm(element)]
        case let (.inductor, .transient(method, h)):
            var flux = stepCoefficient(element, method: method, h: h).negated
            flux.factor = previous(current(element, style: .plain))
            guard method == .trapezoidal else { return [flux] }
            return [flux, Term(negative: true, factor: previous(acrossFactor(element, style: .plain)))]
        case let (.capacitor, .transient(method, h)):
            var charge = stepCoefficient(element, method: method, h: h)
            charge.factor = previous(acrossFactor(element, style: .plain))
            guard method == .trapezoidal else { return [charge] }
            return [charge, Term(factor: previous(current(element, style: .plain)))]
        default:
            return []
        }
    }

    // MARK: Rendering

    /// An entry of A or b as text; empty for zero.
    func render(_ terms: [Term]) -> MathText {
        guard !terms.isEmpty else { return MathText() }
        switch notation {
        case .symbols:
            return SignedText.sum(terms.map { term in
                let coefficient = term.reactive ? "jω·" + term.symbol : term.symbol
                if term.factor.isEmpty {
                    return SignedText(negative: term.negative, text: coefficient.isEmpty ? "1" : coefficient)
                }
                if coefficient.isEmpty { return SignedText(negative: term.negative, text: term.factor) }
                return SignedText(negative: term.negative, text: grouped(coefficient) + "·" + term.factor)
            })
        case .values:
            // Plain numbers add up to one value; terms with a factor stay separate.
            let constants = terms.filter { $0.factor.isEmpty }
            let value = Self.value(constants)
            var parts: [SignedText] = []
            if value.real != 0 || (value.reactive == 0 && constants.count == terms.count) {
                parts.append(SignedText(negative: value.real < 0, text: Self.number(abs(value.real))))
            }
            if value.reactive != 0 {
                parts.append(SignedText(negative: value.reactive < 0, text: "jω·" + Self.number(abs(value.reactive))))
            }
            for term in terms where !term.factor.isEmpty {
                let coefficient = term.negative ? -term.value : term.value
                let text = abs(coefficient) == 1 ? term.factor : Self.number(abs(coefficient)) + "·" + term.factor
                parts.append(SignedText(negative: coefficient < 0, text: text))
            }
            return SignedText.sum(parts)
        }
    }

    /// Wraps a compound coefficient in parentheses before it multiplies something.
    private func grouped(_ coefficient: MathText) -> MathText {
        let text = coefficient.description
        return text.contains("/") || text.contains("·") ? "(" + coefficient + ")" : coefficient
    }

    static func value(_ terms: [Term]) -> Coefficient {
        var result = Coefficient()
        for term in terms {
            let value = term.negative ? -term.value : term.value
            if term.reactive { result.reactive += value } else { result.real += value }
        }
        return result
    }

    // MARK: Descriptions

    private var ruleName: String {
        settings.integrationMethod == .trapezoidal ? "trapezoidal rule" : "backward Euler method"
    }

    var summary: String {
        switch domain {
        case .dc:
            return "DC operating point"
        case let .transient(_, h):
            guard h.isFinite else { return "Transient · \(ruleName)" }
            return "Transient · \(ruleName) · time step h = \(SIFormat.string(h, unit: "s", significantDigits: 4))"
        case .ac:
            let start = SIFormat.string(settings.startFrequency, unit: "Hz")
            let stop = SIFormat.string(settings.stopFrequency, unit: "Hz")
            return "AC sweep · phasors at ω = 2πf, f from \(start) to \(stop)"
        }
    }

    var notes: [String] {
        var notes = [
            "Node rows are Kirchhoff's current law: the currents leaving the node sum to zero. "
                + "Resistors and current sources appear only there, so they have no rows of their own.",
            "I(X) is the current through X from its pin 1 to its pin 2, so a source that delivers power has a negative current.",
        ]
        switch domain {
        case .dc:
            notes.append("At DC, capacitors are open circuits and inductors are short circuits. Sources take their value at t = 0.")
        case .transient:
            notes.append("Each time step solves A·x = b, discretized with the \(ruleName). A subscript n−1 marks a value from the previous step.")
            notes.append(settings.initialConditions == .zero
                ? "At t = 0, capacitors start at 0 V and inductors at 0 A."
                : "At t = 0, the circuit starts from its DC operating point.")
            for element in netlist.elements where element.kind == .currentSource && element.waveform.shape != .dc {
                notes.append("\(element.name)(t) is \(element.waveform.summary(level: element.value, unit: "A")).")
            }
        case .ac:
            notes.append("Sources use their AC magnitude and phase.")
        }
        let kinds = Set(netlist.elements.map(\.kind))
        let deviceNames = [
            kinds.contains(.diode) ? "diodes" : nil,
            kinds.contains(.bjt) || kinds.contains(.mosfet) ? "transistors" : nil,
            kinds.contains(.logicGate) ? "logic gates" : nil,
        ].compactMap { $0 }
        let devices = deviceNames.count > 2
            ? deviceNames.dropLast().joined(separator: ", ") + ", and " + deviceNames.last!
            : deviceNames.joined(separator: " and ")
        if !devices.isEmpty {
            let thermal = SIFormat.string(DiodeModel.thermalVoltage, unit: "V", significantDigits: 4)
            switch domain {
            case .ac:
                notes.append("The \(devices) act as their tangents at the DC operating point (their small-signal models).")
            case .dc, .transient:
                notes.append("\(devices.prefix(1).uppercased() + devices.dropFirst()) are not linear, so the simulator solves "
                    + "for them by Newton–Raphson iteration: each iteration replaces each of their currents by its tangent "
                    + "at the previous iterate (subscript k), whose slopes G or g are ∂I/∂V there, until the solution "
                    + "stops changing. Vt = kT/q = \(thermal) at 27 °C.")
            }
        }
        if kinds.contains(.bjt) {
            notes.append("BJTs follow the Ebers–Moll model with a reverse current gain β_R of 1. Their tangent slopes are the "
                + "hybrid-π parameters: g_m = ∂Ic/∂V_BE, g_π = ∂Ib/∂V_BE, g_μ = ∂Ib/∂V_BC, g_o = −∂Ic/∂V_BC − g_μ. "
                + "A PNP transistor obeys the NPN laws with every voltage and current negated.")
        }
        if kinds.contains(.mosfet) {
            notes.append("MOSFETs follow the square law with the body tied to the source. With V_ov = V_GS − V_th, "
                + "Id is 0 below threshold, k·(V_ov·V_DS − V_DS²/2)·(1 + λ·V_DS) in the triode region (V_DS < V_ov), "
                + "and ½·k·V_ov²·(1 + λ·V_DS) in saturation. Their slopes are g_m = ∂Id/∂V_GS and g_ds = ∂Id/∂V_DS. "
                + "A P-channel device obeys the N-channel laws with every voltage and current negated.")
        }
        if netlist.elements.contains(where: { $0.kind == .opAmp }) {
            notes.append("An op-amp's output is a voltage source to ground of A·(V+ − V−), where A is its open-loop gain. "
                + "Its inputs draw no current, so I(U) — the current into its output — appears only in the output node's law. "
                + "The model is linear: the output does not saturate.")
        }
        if kinds.contains(.logicGate) {
            let resistance = SIFormat.string(LogicGateModel.outputResistance, unit: "Ω")
            notes.append("A logic gate drives its output toward 0 V or its supply V_DD, relative to ground, through R_out = \(resistance): "
                + "I(U), the current into its output, is (V(out) − V_DD·f)/R_out. Its inputs switch at V_DD/2 and draw no current. "
                + "f is the gate's function on the input levels x = 1/(1 + exp(−(V − V_DD/2)/w)), with w = V_DD/100, in place "
                + "of 1s and 0s: AND is x_A·x_B, OR is x_A + x_B − x_A·x_B, NOT is 1 − x_A, so the equations stay smooth. "
                + "G_out = 1/R_out, and g_A and g_B are ∂I/∂V of the inputs.")
            if case .transient = domain {
                notes.append("A gate's output follows its inputs one propagation delay t_pd later: f takes the input voltages "
                    + "at t − t_pd, interpolated between time points. When t_pd is shorter than the time step h, that time "
                    + "falls inside the step, so f also depends on the present, unknown inputs, in proportion 1 − t_pd/h."
                    + (settings.initialConditions == .zero ? " From rest, every gate's output starts at 0 V and stays there for t_pd." : ""))
            }
        }
        notes.append("The simulator also connects \(SIFormat.string(Simulator.gmin, unit: "S")) (gmin) from every node to ground. It is left out here.")
        return notes
    }
}
