import Charts
import CircuitCore
import SwiftUI

struct SimulationPanel: View {
    enum Tab {
        case results, equations
    }

    @ObservedObject var editor: EditorModel
    @ObservedObject var document: CircuitDocument
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let tab = State(initialValue: Tab.results)
    private let notation = State(initialValue: CircuitEquations.Notation.symbols)

    var body: some View {
        VStack(spacing: 0) {
            SimulationSettingsBar(
                editor: editor, settings: document.circuit.simulation,
                tab: tab.projectedValue, notation: notation.projectedValue)
            Divider()
            switch tab.wrappedValue {
            case .results:
                ResultsView(editor: editor)
            case .equations:
                EquationsView(editor: editor, document: document, notation: notation.wrappedValue)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings

private struct SimulationSettingsBar: View {
    @ObservedObject var editor: EditorModel
    let settings: SimulationSettings
    @Binding var tab: SimulationPanel.Tab
    @Binding var notation: CircuitEquations.Notation

    var body: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $tab) {
                Text("Results").tag(SimulationPanel.Tab.results)
                Text("Equations").tag(SimulationPanel.Tab.equations)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show the simulation results, or the equations the simulator solves")
            Divider()
                .frame(height: 16)

            // Scrolls instead of forcing the window wider when space is tight.
            ScrollView(.horizontal, showsIndicators: false) {
                analysisControls
                    .padding(.vertical, 1)
            }
            .scrollBounceBehavior(.basedOnSize)

            switch tab {
            case .results:
                if editor.isSimulating {
                    ProgressView().controlSize(.small)
                }
                Toggle("Auto-run", isOn: $editor.autoRun)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .help("Re-run the simulation automatically after each edit")
                Button {
                    editor.runSimulation()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .fixedSize()
            case .equations:
                Picker("Notation", selection: $notation) {
                    ForEach(CircuitEquations.Notation.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Write the equations with component names or with their values")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var analysisControls: some View {
        HStack(spacing: 12) {
            Picker("Analysis", selection: Binding(
                get: { settings.analysis },
                set: { analysis in editor.updateSettings("Change Analysis") { $0.analysis = analysis } }
            )) {
                ForEach(SimulationSettings.Analysis.allCases, id: \.self) { Text($0.shortName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch settings.analysis {
            case .operatingPoint:
                Text("Capacitors open, inductors shorted, sources at their t = 0 value.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            case .transient:
                SIField(label: "Stop", unit: "s", value: settings.stopTime, range: 1e-15...1e6, fieldWidth: 64) { value in
                    editor.updateSettings { $0.stopTime = value }
                }
                SIField(label: "Step", unit: "s", value: settings.timeStep, emptyPlaceholder: "auto", range: 0...1e6, fieldWidth: 64) { value in
                    editor.updateSettings { $0.timeStep = value }
                }
                .help("Fixed time step. Leave empty for automatic (stop time / 2000).")
                Picker("Start", selection: Binding(
                    get: { settings.initialConditions },
                    set: { value in editor.updateSettings { $0.initialConditions = value } }
                )) {
                    ForEach(SimulationSettings.InitialConditions.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Initial state at t = 0")
                Picker("Method", selection: Binding(
                    get: { settings.integrationMethod },
                    set: { value in editor.updateSettings { $0.integrationMethod = value } }
                )) {
                    ForEach(SimulationSettings.IntegrationMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Numerical integration method")
            case .ac:
                SIField(label: "From", unit: "Hz", value: settings.startFrequency, range: 1e-12...1e15, fieldWidth: 64) { value in
                    editor.updateSettings { $0.startFrequency = value }
                }
                SIField(label: "To", unit: "Hz", value: settings.stopFrequency, range: 1e-12...1e15, fieldWidth: 64) { value in
                    editor.updateSettings { $0.stopFrequency = value }
                }
                SIField(label: "Points/decade", unit: "", value: Double(settings.pointsPerDecade), range: 1...1000, fieldWidth: 44) { value in
                    editor.updateSettings { $0.pointsPerDecade = Int(value.rounded()) }
                }
            }
        }
    }
}

extension SimulationSettings.Analysis {
    var shortName: String {
        switch self {
        case .operatingPoint: "DC Op"
        case .transient: "Transient"
        case .ac: "AC Sweep"
        }
    }
}

// MARK: - Results

private struct ResultsView: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        if let error = editor.simulationError {
            VStack(spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: 560)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if let result = editor.result {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Group {
                        switch result.output {
                        case let .operatingPoint(op):
                            OperatingPointView(netlist: result.netlist, op: op)
                        case let .transient(transient):
                            TransientChartsView(editor: editor, transient: transient)
                        case let .ac(ac):
                            ACChartsView(editor: editor, ac: ac, settings: result.settings)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(editor.resultIsStale ? 0.45 : 1)
                    .overlay(alignment: .top) {
                        if editor.resultIsStale && !editor.isSimulating {
                            Text("The circuit has changed. Run the simulation again to update.")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
                    if case .operatingPoint = result.output {
                        EmptyView()
                    } else {
                        Divider()
                        SignalListView(editor: editor)
                            .frame(width: 190)
                    }
                }
                if !result.netlist.warnings.isEmpty {
                    Divider()
                    WarningsView(warnings: result.netlist.warnings)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Choose an analysis and press Run (⌘↩).")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WarningsView: View {
    let warnings: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(warnings.joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

// MARK: - Operating point

private struct OperatingPointView: View {
    let netlist: Netlist
    let op: OperatingPoint

    private struct NodeRow: Identifiable {
        let id: Int
        let name: String
        let voltage: Double
    }

    private struct ElementRow: Identifiable {
        let id: Int
        let name: String
        let voltage: Double
        let current: Double
        let power: Double
    }

    var body: some View {
        let nodes = (1..<max(1, netlist.nodeCount)).map {
            NodeRow(id: $0, name: netlist.nodeNames[$0], voltage: op.nodeVoltages[$0])
        }
        let elements = netlist.elements.enumerated().map { index, element in
            ElementRow(
                id: index, name: element.name,
                voltage: op.elementVoltages[index],
                current: op.elementCurrents[index],
                power: op.elementPowers[index])
        }
        HStack(spacing: 0) {
            Table(nodes) {
                TableColumn("Net", value: \.name)
                TableColumn("Voltage") { Text(SIFormat.string($0.voltage, unit: "V", significantDigits: 5)).monospacedDigit() }
            }
            .frame(minWidth: 220, idealWidth: 280)
            Divider()
            Table(elements) {
                TableColumn("Element", value: \.name)
                TableColumn("Voltage") { Text(SIFormat.string($0.voltage, unit: "V", significantDigits: 5)).monospacedDigit() }
                TableColumn("Current") { Text(SIFormat.string($0.current, unit: "A", significantDigits: 5)).monospacedDigit() }
                TableColumn("Power") { Text(SIFormat.string($0.power, unit: "W", significantDigits: 4)).monospacedDigit() }
            }
        }
    }
}

// MARK: - Chart data

/// Fixed categorical palette (light / dark steps), validated for color-vision deficiency
/// separation between adjacent slots. Slots are assigned per signal, never by rank.
enum SignalPalette {
    private static let light = [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x008300, 0x6250D6, 0xE34948]
    private static let dark = [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x008300, 0x9085E9, 0xE66767]

    private static let colors: [Color] = zip(light, dark).map { lightHex, darkHex in
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.isDark ? darkHex : lightHex)
        })
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    static func color(_ slot: Int) -> Color { colors[slot % colors.count] }
}

struct ChartPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

/// One plotted line: decimated points for drawing plus full-resolution data for the readout.
struct ChartSeries: Identifiable {
    let id: String
    let slot: Int
    let points: [ChartPoint]
    let xs: [Double]
    let ys: [Double]

    init(id: String, slot: Int, xs: [Double], ys: [Double], maxPoints: Int = 1600) {
        self.id = id
        self.slot = slot
        self.xs = xs
        self.ys = ys
        points = Self.decimate(xs: xs, ys: ys, maxPoints: maxPoints)
    }

    /// Value at the sample nearest to `x` (xs must be ascending).
    func value(near x: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        var low = 0, high = xs.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if xs[mid] < x { low = mid } else { high = mid }
        }
        return abs(xs[low] - x) <= abs(xs[high] - x) ? ys[low] : ys[high]
    }

    /// Min/max decimation: keeps the envelope of dense data so peaks don't disappear.
    private static func decimate(xs: [Double], ys: [Double], maxPoints: Int) -> [ChartPoint] {
        let n = xs.count
        guard n > maxPoints else {
            return (0..<n).map { ChartPoint(id: $0, x: xs[$0], y: ys[$0]) }
        }
        let buckets = maxPoints / 2
        var points: [ChartPoint] = []
        points.reserveCapacity(maxPoints + 2)
        for bucket in 0..<buckets {
            let lo = bucket * n / buckets, hi = max(lo + 1, (bucket + 1) * n / buckets)
            var minIndex = lo, maxIndex = lo
            for i in lo..<hi {
                if ys[i] < ys[minIndex] { minIndex = i }
                if ys[i] > ys[maxIndex] { maxIndex = i }
            }
            for i in Set([minIndex, maxIndex]).sorted() {
                points.append(ChartPoint(id: i, x: xs[i], y: ys[i]))
            }
        }
        if points.last?.id != n - 1 { points.append(ChartPoint(id: n - 1, x: xs[n - 1], y: ys[n - 1])) }
        return points
    }
}

// MARK: - Transient

private struct TransientChartsView: View {
    @ObservedObject var editor: EditorModel
    let transient: TransientResult
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let hoverTime = State<Double?>(initialValue: nil)

    var body: some View {
        let visible = editor.visibleSignals
        let voltages = visible.filter { $0.quantity == .voltage }.map(series)
        let currents = visible.filter { $0.quantity == .current }.map(series)
        let domain = 0...(transient.time.last ?? 1)
        VStack(spacing: 0) {
            if voltages.isEmpty && currents.isEmpty {
                Text("Select signals to plot in the list on the right.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !voltages.isEmpty {
                SignalChart(title: "Voltage", series: voltages, xDomain: domain, xUnit: "s", yUnit: "V", logX: false, hoverX: hoverTime.projectedValue)
            }
            if !voltages.isEmpty && !currents.isEmpty { Divider() }
            if !currents.isEmpty {
                SignalChart(title: "Current", series: currents, xDomain: domain, xUnit: "s", yUnit: "A", logX: false, hoverX: hoverTime.projectedValue)
            }
        }
    }

    private func series(_ signal: Signal) -> ChartSeries {
        let ys = signal.quantity == .voltage ? transient.nodeVoltages[signal.index] : transient.elementCurrents[signal.index]
        return ChartSeries(id: signal.id, slot: editor.signalSlots[signal.id] ?? 0, xs: transient.time, ys: ys)
    }
}

// MARK: - AC

private struct ACChartsView: View {
    @ObservedObject var editor: EditorModel
    let ac: ACResult
    let settings: SimulationSettings
    private let hoverFrequency = State<Double?>(initialValue: nil)

    var body: some View {
        let visible = editor.visibleSignals
        let domain = (ac.frequencies.first ?? 1)...(ac.frequencies.last ?? 10)
        // dBV and dBA are different measures, so they get separate magnitude charts.
        let voltageMagnitudes = visible.filter { $0.quantity == .voltage }.map(magnitude)
        let currentMagnitudes = visible.filter { $0.quantity == .current }.map(magnitude)
        let phases = visible.map { signal in
            ChartSeries(id: signal.id, slot: editor.signalSlots[signal.id] ?? 0, xs: ac.frequencies,
                        ys: Self.unwrappedPhaseDegrees(values(signal)))
        }
        VStack(spacing: 0) {
            if visible.isEmpty {
                Text("Select signals to plot in the list on the right.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !voltageMagnitudes.isEmpty {
                    SignalChart(title: "Voltage magnitude", series: voltageMagnitudes, xDomain: domain, xUnit: "Hz", yUnit: "dBV", logX: true, hoverX: hoverFrequency.projectedValue)
                    Divider()
                }
                if !currentMagnitudes.isEmpty {
                    SignalChart(title: "Current magnitude", series: currentMagnitudes, xDomain: domain, xUnit: "Hz", yUnit: "dBA", logX: true, hoverX: hoverFrequency.projectedValue)
                    Divider()
                }
                SignalChart(title: "Phase", series: phases, xDomain: domain, xUnit: "Hz", yUnit: "°", logX: true, hoverX: hoverFrequency.projectedValue)
            }
        }
    }

    private func magnitude(_ signal: Signal) -> ChartSeries {
        ChartSeries(id: signal.id, slot: editor.signalSlots[signal.id] ?? 0, xs: ac.frequencies,
                    ys: values(signal).map { 20 * log10(max($0.magnitude, 1e-15)) })
    }

    private func values(_ signal: Signal) -> [Complex] {
        signal.quantity == .voltage ? ac.nodeVoltages[signal.index] : ac.elementCurrents[signal.index]
    }

    static func unwrappedPhaseDegrees(_ values: [Complex]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(values.count)
        var offset = 0.0
        var previous: Double?
        for value in values {
            var degrees = value.phase * 180 / .pi
            if let previous {
                let jump = degrees + offset - previous
                if jump > 180 { offset -= 360 } else if jump < -180 { offset += 360 }
            }
            degrees += offset
            result.append(degrees)
            previous = degrees
        }
        return result
    }
}

// MARK: - Chart

private struct SignalChart: View {
    let title: String
    let series: [ChartSeries]
    let xDomain: ClosedRange<Double>
    let xUnit: String
    let yUnit: String
    let logX: Bool
    @Binding var hoverX: Double?

    var body: some View {
        chart
            .chartXScale(domain: xDomain, type: logX ? .log : .linear)
            .chartXAxis {
                if logX {
                    AxisMarks(values: decades) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel { axisLabel(value.as(Double.self), unit: xUnit) }
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel { axisLabel(value.as(Double.self), unit: xUnit) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        // Fixed width keeps the plot areas of stacked charts aligned.
                        axisLabel(value.as(Double.self), unit: yUnit)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                if let x: Double = proxy.value(atX: location.x - origin.x), xDomain.contains(x) {
                                    hoverX = x
                                } else {
                                    hoverX = nil
                                }
                            case .ended:
                                hoverX = nil
                            }
                        }
                }
            }
            .overlay(alignment: .topTrailing) { readout }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
    }

    private var chart: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { point in
                    LineMark(
                        x: .value(xUnit, point.x),
                        y: .value(title, point.y),
                        series: .value("Signal", s.id))
                        .foregroundStyle(SignalPalette.color(s.slot))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let hoverX {
                RuleMark(x: .value(xUnit, hoverX))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(series) { s in
                    if let y = s.value(near: hoverX) {
                        PointMark(x: .value(xUnit, hoverX), y: .value(title, y))
                            .foregroundStyle(SignalPalette.color(s.slot))
                            .symbolSize(40)
                    }
                }
            }
        }
    }

    /// Crosshair readout: x value and each series' value at the pointer.
    @ViewBuilder
    private var readout: some View {
        if let hoverX {
            VStack(alignment: .leading, spacing: 2) {
                Text(SIFormat.string(hoverX, unit: xUnit, significantDigits: 4))
                    .font(.caption.weight(.semibold))
                ForEach(series) { s in
                    if let y = s.value(near: hoverX) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(SignalPalette.color(s.slot))
                                .frame(width: 10, height: 3)
                            Text(s.id)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(format(y, unit: yUnit))
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
            }
            .padding(6)
            .frame(minWidth: 150)
            .fixedSize()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 2)
            .allowsHitTesting(false)
        } else {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var decades: [Double] {
        let low = Int(floor(log10(xDomain.lowerBound))), high = Int(ceil(log10(xDomain.upperBound)))
        return (low...max(low, high)).map { pow(10, Double($0)) }.filter { xDomain.contains($0) }
    }

    private func format(_ value: Double, unit: String) -> String {
        if unit.hasPrefix("dB") { return String(format: "%.2f %@", value, unit) }
        if unit == "°" { return String(format: "%.1f°", value) }
        return SIFormat.string(value, unit: unit, significantDigits: 4)
    }

    /// Logarithmic quantities keep plain numbers; linear ones get SI prefixes.
    private func axisLabel(_ value: Double?, unit: String) -> Text {
        guard let value else { return Text("") }
        if unit.hasPrefix("dB") { return Text(String(format: "%g %@", value, unit)) }
        if unit == "°" { return Text(String(format: "%g°", value)) }
        return Text(SIFormat.string(value, unit: unit))
    }
}

// MARK: - Signal list (legend)

private struct SignalListView: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let signals = editor.signals
        let full = editor.signalSlots.count >= EditorModel.maxVisibleSignals
        List {
            Section("Voltages") {
                ForEach(signals.filter { $0.quantity == .voltage }) { row($0, disabled: full) }
            }
            Section("Currents") {
                ForEach(signals.filter { $0.quantity == .current }) { row($0, disabled: full) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func row(_ signal: Signal, disabled: Bool) -> some View {
        let visible = editor.isVisible(signal)
        return Toggle(isOn: Binding(get: { visible }, set: { editor.setVisible(signal, $0) })) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(visible ? SignalPalette.color(editor.signalSlots[signal.id] ?? 0) : Color.clear)
                    .overlay {
                        if !visible { RoundedRectangle(cornerRadius: 1.5).stroke(Color.secondary.opacity(0.4)) }
                    }
                    .frame(width: 14, height: 4)
                Text(signal.id)
                    .font(.callout.monospaced())
                    .lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(disabled && !visible)
        .help(disabled && !visible ? "Up to \(EditorModel.maxVisibleSignals) signals can be plotted at once" : "")
        .onHover { hovering in
            guard signal.quantity == .voltage else { return }
            editor.highlightedNode = hovering ? signal.index : nil
        }
    }
}
