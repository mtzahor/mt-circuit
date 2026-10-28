import CircuitCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: CircuitDocument
    @StateObject private var editor: EditorModel
    @StateObject private var tutorial: TutorialModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let showInspector = State(initialValue: true)

    init(document: CircuitDocument) {
        self.document = document
        _editor = StateObject(wrappedValue: EditorModel(document: document))
        _tutorial = StateObject(wrappedValue: TutorialModel(document: document))
    }

    var body: some View {
        HSplitView {
            if let lesson = tutorial.lesson {
                LessonPanel(editor: editor, tutorial: tutorial, lesson: lesson)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
            }
            VSplitView {
                SchematicEditorView(editor: editor)
                    .frame(minHeight: 260, idealHeight: 500)
                    .overlay(alignment: .bottomLeading) { ToolHint(tool: editor.tool) }
                    .overlay {
                        if document.circuit.isEmpty && document.circuit.lesson == nil && editor.tool == .select {
                            EmptyCircuitView(editor: editor)
                        }
                    }
                SimulationPanel(editor: editor, document: document)
                    .frame(minHeight: 180, idealHeight: 300)
            }
            .frame(minWidth: 400)
        }
        .inspector(isPresented: showInspector.projectedValue) {
            InspectorView(editor: editor, document: document)
                .inspectorColumnWidth(min: 250, ideal: 290, max: 420)
        }
        .toolbar { toolbarContent }
        .onAppear {
            editor.undoManager = undoManager
            editor.openDiveIn = { [openWindow] topic in openWindow.diveIn(to: topic.id) }
            // A lesson simulates from the start, even an empty one, so that its errors guide the learner.
            if !document.circuit.isEmpty || document.circuit.lesson != nil { editor.runSimulation() }
        }
        .onChange(of: undoManager) { _, manager in editor.undoManager = manager }
        .focusedSceneObject(editor)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Tool", selection: Binding(get: { editor.tool }, set: { editor.selectTool($0) })) {
                ForEach(EditorTool.palette) { tool in
                    toolImage(tool)
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .accessibilityLabel(tool.title)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .help("Tools: S select, W wire, R C L D Q M V I O G N place parts")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { editor.rotate() } label: { Label("Rotate", systemImage: "rotate.right") }
                .help("Rotate (Space or ⌘R)")
            Button { editor.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                .help("Delete selection (⌫)")
                .disabled(editor.selection.isEmpty)
            Button { editor.runSimulation() } label: { Label("Run", systemImage: "play.fill") }
                .help("Run simulation (⌘↩)")
            Button { showInspector.wrappedValue.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help("Show or hide the inspector")
        }
    }

    @ViewBuilder
    private func toolImage(_ tool: EditorTool) -> some View {
        if tool == .select {
            Image(systemName: "cursorarrow")
        } else {
            Image(nsImage: SymbolRenderer.icon(for: tool))
        }
    }
}

/// Hosts the AppKit schematic canvas in a magnifiable scroll view.
struct SchematicEditorView: NSViewRepresentable {
    let editor: EditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = SchematicCanvasView(editor: editor)
        let scrollView = NSScrollView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SchematicStyle.background
        editor.canvas = canvas
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

private struct ToolHint: View {
    let tool: EditorTool

    var body: some View {
        Text(tool.hint)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(10)
            .allowsHitTesting(false)
    }
}

/// Onboarding shown on a blank schematic.
private struct EmptyCircuitView: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            Text("Start a circuit")
                .font(.title2.weight(.semibold))
            Text("Pick a part from the toolbar (or press R, C, L, V, G) and click to place it.\nPress W to draw wires between pins. Every circuit needs a ground.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Start the Tutorial") { editor.startLesson(TutorialProgress.shared.nextLesson) }
                    .help("Learn the fundamentals of electronics, with a challenge in each lesson")
                Menu("Load an Example") {
                    ForEach(Examples.all, id: \.name) { example in
                        Button(example.name) { editor.loadExample(example) }
                    }
                }
                .fixedSize()
                Button("Dive In") { openWindow.diveIn() }
                    .help("See what's inside each part, from the op-amp down to the pn junction")
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
