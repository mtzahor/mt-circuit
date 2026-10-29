import CircuitCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var document: CircuitDocument

    var body: some View {
        let selected = editor.selectedComponents
        Group {
            if selected.count == 1, editor.selection.count == 1 {
                ComponentInspector(editor: editor, component: selected[0])
                    .id(selected[0].id)
            } else if !editor.selection.isEmpty {
                SelectionSummary(editor: editor)
            } else {
                CircuitSummary(circuit: document.circuit)
            }
        }
    }
}

// MARK: - Single component

private struct ComponentInspector: View {
    @ObservedObject var editor: EditorModel
    let component: Component

    private var kind: ComponentKind { component.kind }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: component.logic.map { SymbolRenderer.icon(for: $0.function) } ?? SymbolRenderer.icon(for: .place(kind)))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(kind == .netLabel ? component.name : "\(component.name)")
                            .font(.headline)
                        Text(component.logic.map { "\($0.function.displayName) Gate" } ?? kind.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if DiveIn.topic(for: component) != nil {
                        Spacer()
                        Button { editor.diveIn() } label: {
                            Label("Dive In", systemImage: "water.waves.and.arrow.down")
                        }
                        .controlSize(.small)
                        .help("See what's inside a \(kind.displayName.lowercased()) (⌘↓)")
                    }
                }
            }

            Section("Properties") {
                if kind != .ground {
                    CommitTextField(label: kind == .netLabel ? "Net name" : "Name", value: component.name) { name in
                        editor.updateComponent(component.id, "Rename") { $0.name = name }
                    }
                }
                if kind.isTransistor {
                    Picker("Type", selection: Binding(
                        get: { component.transistor?.polarity ?? .n },
                        set: { polarity in editor.updateComponent(component.id, "Change Transistor Type") { $0.transistor?.polarity = polarity } }
                    )) {
                        Text(kind == .bjt ? "NPN" : "N-channel").tag(TransistorParameters.Polarity.n)
                        Text(kind == .bjt ? "PNP" : "P-channel").tag(TransistorParameters.Polarity.p)
                    }
                }
                if kind == .logicGate {
                    Picker("Function", selection: Binding(
                        get: { component.logic?.function ?? .and },
                        set: { function in
                            editor.placementGate = function
                            editor.updateComponent(component.id, "Change Gate Function") { component in
                                var parameters = component.logic ?? LogicParameters()
                                parameters.function = function
                                component.logic = parameters
                            }
                        }
                    )) {
                        ForEach(LogicFunction.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                if kind.hasValue && !kind.isSource {
                    // A MOSFET's threshold may be zero or negative (depletion mode).
                    let range = kind == .mosfet ? -1e3...1e3 : 1e-18...1e18
                    SIField(label: valueLabel, unit: kind.unitSymbol, value: component.value, range: range) { value in
                        editor.updateComponent(component.id, "Change \(valueLabel)") { $0.value = value }
                    }
                }
                if kind == .bjt {
                    transistorField("Saturation current", "A", \.saturationCurrent, range: 1e-30...1)
                    transistorField("Early voltage", "V", \.earlyVoltage, emptyPlaceholder: "none", range: 0...1e6)
                }
                if kind == .mosfet {
                    transistorField("Transconductance k", "A/V²", \.transconductance, range: 1e-12...1e3)
                    transistorField("λ", "1/V", \.channelLengthModulation, emptyPlaceholder: "none", range: 0...10)
                }
                if kind == .logicGate {
                    SIField(
                        label: "Propagation delay", unit: "s", value: component.logic?.delay ?? LogicParameters.defaultDelay,
                        emptyPlaceholder: "none", range: 0...1
                    ) { delay in
                        editor.updateComponent(component.id, "Change Propagation Delay") { component in
                            var parameters = component.logic ?? LogicParameters()
                            parameters.delay = delay
                            component.logic = parameters
                        }
                    }
                }
                if kind == .diode {
                    SIField(label: "Emission coefficient", unit: "", value: component.emissionCoefficient ?? 1, range: 0.01...100) { value in
                        editor.updateComponent(component.id, "Change Emission Coefficient") { $0.emissionCoefficient = value }
                    }
                }
                if kind != .netLabel {
                    LabeledContent("Rotation") {
                        HStack {
                            Text("\(component.rotation * 90)°").monospacedDigit()
                            Button { editor.rotate() } label: { Image(systemName: "rotate.right") }
                                .buttonStyle(.borderless)
                                .help("Rotate 90° clockwise")
                        }
                    }
                }
                if kind == .netLabel {
                    Text("Net labels name a net in simulation results. Labels with the same name are connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .ground {
                    Text("All ground symbols are the 0 V reference node.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .diode {
                    Text("Shockley model: I = Is·(exp(V/(n·Vt)) − 1), with Vt = \(SIFormat.string(DiodeModel.thermalVoltage, unit: "V", significantDigits: 4)). "
                        + "Pin 1 is the anode. There is no series resistance, junction capacitance, or reverse breakdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .bjt {
                    Text("Ebers–Moll model with the Early effect and a reverse gain of 1; no junction capacitance. "
                        + "A PNP transistor is drawn upside down, with its emitter on top.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .mosfet {
                    Text("Square-law model with the body tied to the source: Id = ½·k·(VGS − Vth)²·(1 + λ·VDS) in saturation; "
                        + "no capacitances. A P-channel device is drawn upside down, with its source on top, and conducts when VGS < −Vth.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .opAmp {
                    Text("The output is A·(V+ − V−) relative to ground, and the inputs draw no current. "
                        + "The model is linear: there are no supply rails, so the output does not saturate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if kind == .logicGate {
                    Text("The output drives toward 0 V or the supply voltage, relative to ground, through "
                        + "\(SIFormat.string(LogicGateModel.outputResistance, unit: "Ω")); there are no power pins. "
                        + "Inputs switch at half the supply and draw no current. The output follows them after the propagation delay.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if kind.isSource {
                SourceSection(editor: editor, component: component)
            }

            OperatingPointSection(editor: editor, component: component)
        }
        .formStyle(.grouped)
    }

    private func transistorField(
        _ label: String, _ unit: String, _ keyPath: WritableKeyPath<TransistorParameters, Double>,
        emptyPlaceholder: String? = nil, range: ClosedRange<Double>
    ) -> some View {
        let parameters = component.transistor ?? TransistorParameters()
        return SIField(label: label, unit: unit, value: parameters[keyPath: keyPath], emptyPlaceholder: emptyPlaceholder, range: range) { value in
            editor.updateComponent(component.id, "Change \(label)") { component in
                var parameters = component.transistor ?? TransistorParameters()
                parameters[keyPath: keyPath] = value
                component.transistor = parameters
            }
        }
    }

    private var valueLabel: String {
        switch kind {
        case .resistor: "Resistance"
        case .capacitor: "Capacitance"
        case .inductor: "Inductance"
        case .diode: "Saturation current"
        case .bjt: "Current gain β"
        case .mosfet: "Threshold voltage"
        case .opAmp: "Open-loop gain"
        case .logicGate: "Supply voltage"
        default: "Value"
        }
    }
}

private struct SourceSection: View {
    @ObservedObject var editor: EditorModel
    let component: Component

    private var unit: String { component.kind.unitSymbol }
    private var waveform: SourceWaveform { component.waveform }

    var body: some View {
        Section("Waveform") {
            Picker("Shape", selection: Binding(
                get: { waveform.shape },
                set: { shape in editor.updateComponent(component.id, "Change Waveform") { $0.waveform.shape = shape } }
            )) {
                ForEach(SourceWaveform.Shape.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            switch waveform.shape {
            case .dc:
                levelField(component.kind == .voltageSource ? "Voltage" : "Current")
            case .step:
                field("Initial value", unit, \.initialValue)
                levelField("Final value")
                field("Delay", "s", \.delay, range: 0...1e6)
                field("Rise time", "s", \.riseTime, range: 0...1e6)
            case .sine:
                levelField("Offset")
                field("Amplitude", unit, \.amplitude)
                field("Frequency", "Hz", \.frequency, range: 0...1e15)
                field("Phase", "°", \.phase)
                field("Delay", "s", \.delay, range: 0...1e6)
            case .pulse:
                field("Initial value", unit, \.initialValue)
                levelField("Pulsed value")
                field("Delay", "s", \.delay, range: 0...1e6)
                field("Rise time", "s", \.riseTime, range: 0...1e6)
                field("Width", "s", \.pulseWidth, range: 0...1e6)
                field("Fall time", "s", \.fallTime, range: 0...1e6)
                field("Period", "s", \.period, range: 0...1e6)
            }
        }
        Section {
            field("Magnitude", unit, \.acMagnitude)
            field("Phase", "°", \.acPhase)
        } header: {
            Text("AC Analysis")
        } footer: {
            Text("Small-signal amplitude used by the AC sweep.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func levelField(_ label: String) -> some View {
        SIField(label: label, unit: unit, value: component.value) { value in
            editor.updateComponent(component.id, "Change \(label)") { $0.value = value }
        }
    }

    private func field(_ label: String, _ unit: String, _ keyPath: WritableKeyPath<SourceWaveform, Double>, range: ClosedRange<Double>? = nil) -> some View {
        SIField(label: label, unit: unit, value: waveform[keyPath: keyPath], range: range) { value in
            editor.updateComponent(component.id, "Change \(label)") { $0.waveform[keyPath: keyPath] = value }
        }
    }
}

/// DC voltage, current, and power of the selected element after an operating-point analysis.
private struct OperatingPointSection: View {
    @ObservedObject var editor: EditorModel
    let component: Component

    private func row(_ label: String, _ value: Double, _ unit: String) -> some View {
        LabeledContent(label, value: SIFormat.string(value, unit: unit, significantDigits: 4))
    }

    /// A logic voltage with the level it stands for: "4.98 V = 1".
    private func levelRow(_ label: String, _ voltage: Double, _ gate: LogicGateModel) -> some View {
        let level = gate.logicValue(voltage).map { $0 ? "1" : "0" } ?? "neither 0 nor 1"
        return LabeledContent(label, value: "\(SIFormat.string(voltage, unit: "V", significantDigits: 4)) = \(level)")
    }

    var body: some View {
        if let result = editor.result, !editor.resultIsStale,
           case let .operatingPoint(op) = result.output,
           let index = result.netlist.elements.firstIndex(where: { $0.componentID == component.id }) {
            let element = result.netlist.elements[index]
            let voltage = op.elementVoltages[index]
            let current = op.elementCurrents[index]
            // Voltage between two of the element's pins.
            let v = { (p: Int, n: Int) in op.nodeVoltages[element.nodes[p]] - op.nodeVoltages[element.nodes[n]] }
            Section {
                switch element.kind {
                case .opAmp:
                    let input = op.nodeVoltages[element.nodeA] - op.nodeVoltages[element.nodeB]
                    row("Input (V+ − V−)", input, "V")
                    row("Output voltage", voltage, "V")
                    row("Current into output", current, "A")
                case .bjt:
                    // Pins: collector 0, base 1, emitter 2.
                    let (vbe, vbc) = (v(1, 2), v(1, 0))
                    let base = element.bjt.currents(vbe: vbe, vbc: vbc).base
                    LabeledContent("Region", value: element.bjt.region(vbe: vbe, vbc: vbc).rawValue.capitalized)
                    row("Base–emitter voltage", vbe, "V")
                    row("Collector–emitter voltage", voltage, "V")
                    row("Collector current", current, "A")
                    row("Base current", base, "A")
                    row("Emitter current", -(current + base), "A")
                case .mosfet:
                    // Pins: drain 0, gate 1, source 2.
                    let vgs = v(1, 2)
                    LabeledContent("Region", value: element.mosfet.region(vgs: vgs, vds: voltage).rawValue.capitalized)
                    row("Gate–source voltage", vgs, "V")
                    row("Drain–source voltage", voltage, "V")
                    row("Drain current", current, "A")
                case .logicGate:
                    let gate = element.gate
                    let inputs = element.inputNodes.count == 1 ? ["Input"] : ["Input A", "Input B"]
                    ForEach(Array(zip(inputs, element.inputNodes)), id: \.0) { name, node in
                        levelRow(name, op.nodeVoltages[node], gate)
                    }
                    levelRow("Output", voltage, gate)
                    row("Current into output", current, "A")
                default:
                    row("Voltage (pin 1 − pin 2)", voltage, "V")
                    row("Current (pin 1 → pin 2)", current, "A")
                }
                row("Power absorbed", op.elementPowers[index], "W")
            } header: {
                Text("DC Operating Point")
            } footer: {
                if element.kind.isTransistor || element.kind == .logicGate {
                    Text("Currents are positive into the pin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
    }
}

// MARK: - Multiple / no selection

private struct SelectionSummary: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Selected", value: "\(editor.selection.count) items")
                HStack {
                    Button("Rotate") { editor.rotate() }
                    Button("Duplicate") { editor.duplicateSelection() }
                    Button("Delete", role: .destructive) { editor.deleteSelection() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CircuitSummary: View {
    let circuit: Circuit

    var body: some View {
        Form {
            Section("Circuit") {
                ForEach([ComponentKind.resistor, .capacitor, .inductor, .diode, .bjt, .mosfet, .voltageSource, .currentSource, .opAmp, .logicGate], id: \.self) { kind in
                    let count = circuit.components.filter { $0.kind == kind }.count
                    if count > 0 {
                        LabeledContent(kind.displayName + "s", value: "\(count)")
                    }
                }
                LabeledContent("Wires", value: "\(circuit.wires.count)")
            }
            Section("Shortcuts") {
                shortcut("S / Esc", "Select tool")
                shortcut("W", "Draw wire")
                shortcut("R C L", "Resistor, capacitor, inductor")
                shortcut("D", "Diode")
                shortcut("Q M", "BJT, MOSFET")
                shortcut("V I", "Voltage, current source")
                shortcut("O", "Op-amp")
                shortcut("A", "Logic gate")
                shortcut("G N", "Ground, net label")
                shortcut("Space", "Rotate")
                shortcut("⌫", "Delete")
                shortcut("⌘↩", "Run simulation")
                shortcut("Pinch / ⌘+ ⌘−", "Zoom")
            }
            Section("Values") {
                Text("Type values with SI prefixes: 4.7k, 10u (or 10µ), 100n, 2p2, 1meg. \"m\" is milli, \"M\" or \"meg\" is mega.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcut(_ keys: String, _ action: String) -> some View {
        LabeledContent(action) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
