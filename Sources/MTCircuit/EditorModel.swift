import AppKit
import CircuitCore
import Combine
import SwiftUI

enum EditorTool: Hashable, Identifiable {
    case select
    case wire
    case place(ComponentKind)

    static let palette: [EditorTool] = [
        .select, .wire,
        .place(.resistor), .place(.capacitor), .place(.inductor), .place(.diode), .place(.bjt), .place(.mosfet),
        .place(.voltageSource), .place(.currentSource), .place(.opAmp), .place(.ground), .place(.netLabel),
    ]

    var id: String {
        switch self {
        case .select: "select"
        case .wire: "wire"
        case let .place(kind): kind.rawValue
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .wire: "Wire"
        case let .place(kind): kind.displayName
        }
    }

    /// Single-key shortcut handled by the schematic canvas.
    var key: Character {
        switch self {
        case .select: "s"
        case .wire: "w"
        case let .place(kind):
            switch kind {
            case .resistor: "r"
            case .capacitor: "c"
            case .inductor: "l"
            case .diode: "d"
            case .bjt: "q"
            case .mosfet: "m"
            case .voltageSource: "v"
            case .currentSource: "i"
            case .opAmp: "o"
            case .ground: "g"
            case .netLabel: "n"
            }
        }
    }

    var hint: String {
        switch self {
        case .select: "Click to select, drag to move, drag on empty space to box-select. Space rotates."
        case .wire: "Click to start a wire, click to add corners; it ends on a pin or wire. Esc cancels."
        case .place(.netLabel): "Click on a wire or pin to name its net. Labels with the same name are connected."
        case let .place(kind): "Click to place a \(kind.displayName.lowercased()). Space or right-click rotates. Esc returns to Select."
        }
    }
}

/// A plottable simulation quantity.
struct Signal: Identifiable, Hashable {
    enum Quantity { case voltage, current }

    let id: String
    let quantity: Quantity
    /// Node index (voltages) or netlist element index (currents).
    let index: Int

    var unit: String { quantity == .voltage ? "V" : "A" }
}

/// Per-window editing state: tool, selection, clipboard, and simulation results.
@MainActor
final class EditorModel: ObservableObject {
    static let maxVisibleSignals = 8

    let document: CircuitDocument
    var undoManager: UndoManager?
    weak var canvas: SchematicCanvasView?

    @Published var tool: EditorTool = .select
    @Published var selection: Set<UUID> = []
    @Published var placementRotation = 0

    @Published private(set) var result: SimulationResult?
    @Published private(set) var resultIsStale = false
    @Published private(set) var simulationError: String?
    @Published private(set) var isSimulating = false
    @Published var autoRun = true
    /// Visible signals, each with a fixed palette slot for as long as it stays visible.
    @Published private(set) var signalSlots: [String: Int] = [:]
    /// Node to highlight in the schematic (hovering a signal in the results list).
    @Published var highlightedNode: Int?

    private var simulationTask: Task<Void, Never>?
    private var autoRunTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private static let pasteboardType = NSPasteboard.PasteboardType("com.mtcircuit.clipboard")

    init(document: CircuitDocument) {
        self.document = document
        document.$circuit
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.circuitDidChange() }
            .store(in: &cancellables)
    }

    var circuit: Circuit { document.circuit }

    var selectedComponents: [Component] {
        circuit.components.filter { selection.contains($0.id) }
    }

    // MARK: - Editing

    func update(_ actionName: String, _ change: (inout Circuit) -> Void) {
        document.update(actionName, undoManager: undoManager, change)
    }

    func selectTool(_ newTool: EditorTool) {
        tool = newTool
        if case let .place(kind) = newTool { placementRotation = kind.defaultRotation }
    }

    func place(_ kind: ComponentKind, at point: GridPoint) {
        var newID: UUID?
        update("Add \(kind.displayName)") { circuit in
            let component = Component(kind: kind, name: circuit.nextName(for: kind), position: point, rotation: placementRotation)
            circuit.components.append(component)
            newID = component.id
        }
        if let newID { selection = [newID] }
    }

    func addWire(from start: GridPoint, to end: GridPoint, horizontalFirst: Bool) {
        update("Add Wire") { $0.addWire(from: start, to: end, horizontalFirst: horizontalFirst) }
    }

    func moveSelection(by offset: GridPoint) {
        guard offset != .zero, !selection.isEmpty else { return }
        let ids = selection
        update("Move") { $0 = $0.moving(ids, by: offset) }
    }

    func rotate() {
        if case .place = tool {
            placementRotation = (placementRotation + 1) % 4
        } else if !selection.isEmpty {
            let ids = selection
            update("Rotate") { $0 = $0.rotating(ids) }
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let ids = selection
        update(ids.count == 1 ? "Delete" : "Delete \(ids.count) Items") { $0 = $0.deleting(ids) }
        selection = []
    }

    func selectAll() {
        tool = .select
        selection = circuit.allIDs
    }

    func updateComponent(_ id: UUID, _ actionName: String, _ change: (inout Component) -> Void) {
        update(actionName) { circuit in
            guard let index = circuit.components.firstIndex(where: { $0.id == id }) else { return }
            change(&circuit.components[index])
        }
    }

    func updateSettings(_ actionName: String = "Change Simulation Settings", _ change: (inout SimulationSettings) -> Void) {
        update(actionName) { change(&$0.simulation) }
    }

    func loadExample(_ example: Examples.Example) {
        load(example.circuit, actionName: "Load Example")
    }

    // MARK: - Tutorial

    /// Replaces the circuit with the lesson's starting circuit, which puts the window in the tutorial.
    func startLesson(_ lesson: Lesson) {
        load(lesson.startingCircuit, actionName: "Start Lesson")
    }

    func loadSolution(of lesson: Lesson) {
        load(lesson.solvedCircuit, actionName: "Load Solution")
    }

    /// Keeps the circuit as an ordinary schematic.
    func leaveTutorial() {
        update("Leave Tutorial") { $0.lesson = nil }
    }

    private func load(_ circuit: Circuit, actionName: String) {
        document.replace(with: circuit, actionName: actionName, undoManager: undoManager)
        selection = []
        selectTool(.select)
        canvas?.zoomToFit()
        runSimulation()
    }

    // MARK: - Dive In

    /// Opens the Dive In window on a topic. Set by the window's content view, which can open windows.
    var openDiveIn: ((DiveInTopic) -> Void)?

    /// The topic about the selected part, when the selection is a single part.
    var diveInTopic: DiveInTopic? {
        guard selection.count == 1, let component = selectedComponents.first else { return nil }
        return DiveIn.topic(for: component.kind)
    }

    func diveIn() {
        guard let topic = diveInTopic else { return }
        openDiveIn?(topic)
    }

    // MARK: - Clipboard

    func copySelection() {
        guard !selection.isEmpty, let data = try? circuit.extracting(selection).encoded() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.pasteboardType)
    }

    var canPaste: Bool {
        NSPasteboard.general.data(forType: Self.pasteboardType) != nil
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    /// Pastes the clipboard so its top-left corner lands at `target` (or slightly offset if nil).
    func paste(at target: GridPoint?) {
        guard let data = NSPasteboard.general.data(forType: Self.pasteboardType),
              let clip = try? Circuit.decoded(from: data) else { return }
        insert(clip, at: target, actionName: "Paste")
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        insert(circuit.extracting(selection), at: nil, actionName: "Duplicate")
    }

    private func insert(_ clip: Circuit, at target: GridPoint?, actionName: String) {
        let points = clip.components.flatMap(\.pinPositions) + clip.wires.flatMap { [$0.start, $0.end] }
        guard let minX = points.map(\.x).min(), let minY = points.map(\.y).min() else { return }
        let offset = target.map { $0 - GridPoint(minX, minY) } ?? GridPoint(2, 2)
        var inserted = Set<UUID>()
        update(actionName) { inserted = $0.paste(clip, offset: offset) }
        tool = .select
        selection = inserted
    }

    // MARK: - Simulation

    func runSimulation() {
        simulationTask?.cancel()
        autoRunTask?.cancel()
        let circuit = self.circuit
        isSimulating = true
        simulationTask = Task { [weak self] in
            let outcome: Result<SimulationResult, Error>
            do {
                outcome = .success(try await Self.simulate(circuit))
            } catch {
                outcome = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.finishSimulation(outcome)
        }
    }

    @concurrent
    private nonisolated static func simulate(_ circuit: Circuit) async throws -> SimulationResult {
        try Simulator.run(circuit)
    }

    private func finishSimulation(_ outcome: Result<SimulationResult, Error>) {
        isSimulating = false
        switch outcome {
        case let .success(result):
            self.result = result
            resultIsStale = false
            simulationError = nil
            refreshVisibleSignals()
        case let .failure(error):
            if case SimulationError.cancelled = error { return }
            simulationError = error.localizedDescription
            resultIsStale = true
        }
    }

    private func circuitDidChange() {
        let ids = circuit.allIDs
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
        guard result != nil || simulationError != nil else { return }
        resultIsStale = true
        guard autoRun else { return }
        autoRunTask?.cancel()
        autoRunTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.runSimulation()
        }
    }

    // MARK: - Signals

    var signals: [Signal] {
        guard let netlist = result?.netlist else { return [] }
        let voltages = (1..<max(1, netlist.nodeCount)).map {
            Signal(id: "V(\(netlist.nodeNames[$0]))", quantity: .voltage, index: $0)
        }
        let currents = netlist.elements.enumerated().map { index, element in
            Signal(id: element.currentNames[0], quantity: .current, index: index)
        }
        return voltages + currents
    }

    var visibleSignals: [Signal] {
        signals.filter { signalSlots[$0.id] != nil }
    }

    func isVisible(_ signal: Signal) -> Bool { signalSlots[signal.id] != nil }

    func setVisible(_ signal: Signal, _ visible: Bool) {
        if !visible {
            signalSlots[signal.id] = nil
        } else if signalSlots[signal.id] == nil, signalSlots.count < Self.maxVisibleSignals {
            let used = Set(signalSlots.values)
            signalSlots[signal.id] = (0..<Self.maxVisibleSignals).first { !used.contains($0) }
        }
    }

    /// Keeps the visible signals that still exist; picks sensible defaults when none remain.
    private func refreshVisibleSignals() {
        let available = Set(signals.map(\.id))
        signalSlots = signalSlots.filter { available.contains($0.key) }
        guard signalSlots.isEmpty, let netlist = result?.netlist else { return }
        let voltages = signals.filter { $0.quantity == .voltage }
        let labelled = voltages.filter { signal in
            let name = netlist.nodeNames[signal.index]
            return !(name.hasPrefix("N") && Int(name.dropFirst()) != nil)
        }
        for signal in (labelled.isEmpty ? voltages : labelled).prefix(4) {
            setVisible(signal, true)
        }
    }
}
