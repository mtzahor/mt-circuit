import CircuitCore
import SwiftUI

@main
struct MTCircuitApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { CircuitDocument() }) { file in
            ContentView(document: file.document)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { CircuitCommands() }

        Window("Dive In", id: DiveInModel.windowID) {
            DiveInView()
        }
        .defaultSize(width: 1060, height: 800)
    }
}

struct CircuitCommands: Commands {
    @FocusedObject private var editor: EditorModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            ExamplesMenu()
            TutorialMenuItem()
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Duplicate") { editor?.duplicateSelection() }
                .keyboardShortcut("d")
                .disabled(editor?.selection.isEmpty ?? true)
            Button("Rotate") { editor?.rotate() }
                .keyboardShortcut("r")
                .disabled(editor == nil)
        }
        CommandMenu("Simulation") {
            Button("Run Simulation") { editor?.runSimulation() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(editor == nil)
            Divider()
            ForEach(SimulationSettings.Analysis.allCases, id: \.self) { analysis in
                Button(analysis.displayName) {
                    editor?.updateSettings("Change Analysis") { $0.analysis = analysis }
                }
                .disabled(editor == nil)
            }
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor?.canvas?.zoom(by: 1.25) }
                .keyboardShortcut("=")
            Button("Zoom Out") { editor?.canvas?.zoom(by: 0.8) }
                .keyboardShortcut("-")
            Button("Actual Size") { editor?.canvas?.setZoom(1) }
                .keyboardShortcut("0")
            Button("Zoom to Fit") { editor?.canvas?.zoomToFit() }
                .keyboardShortcut("9")
            Divider()
            Button(editor?.diveInTopic.map { "Dive Into \($0.title)" } ?? "Dive In") { editor?.diveIn() }
                .keyboardShortcut(.downArrow)
                .disabled(editor?.diveInTopic == nil)
            Divider()
        }
    }
}

/// File ▸ New from Example: opens an example circuit in a new window.
struct ExamplesMenu: View {
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Menu("New from Example") {
            ForEach(Examples.all, id: \.name) { example in
                Button(example.name) {
                    newDocument { CircuitDocument(circuit: example.circuit) }
                }
            }
        }
    }
}

/// File ▸ Start Tutorial: opens the first lesson not completed yet in a new window.
struct TutorialMenuItem: View {
    @Environment(\.newDocument) private var newDocument

    var body: some View {
        Button("Start Tutorial") {
            let circuit = TutorialProgress.shared.nextLesson.startingCircuit
            newDocument { CircuitDocument(circuit: circuit) }
        }
    }
}
