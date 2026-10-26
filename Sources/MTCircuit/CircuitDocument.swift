import CircuitCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Packaging/Info.plist (UTExportedTypeDeclarations).
    static let mtCircuit = UTType(exportedAs: "com.mtcircuit.circuit", conformingTo: .json)
}

/// A schematic file. Every edit goes through `replace(with:actionName:undoManager:)` so it is undoable
/// and marks the document as edited.
final class CircuitDocument: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.mtCircuit] }

    @Published private(set) var circuit: Circuit

    init(circuit: Circuit = Circuit()) {
        self.circuit = circuit
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        circuit = try Circuit.decoded(from: data)
    }

    func snapshot(contentType: UTType) throws -> Circuit {
        circuit
    }

    func fileWrapper(snapshot: Circuit, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }

    /// Applies `change` as a single undoable action (no-op if nothing changed).
    func update(_ actionName: String, undoManager: UndoManager?, _ change: (inout Circuit) -> Void) {
        var new = circuit
        change(&new)
        guard new != circuit else { return }
        replace(with: new, actionName: actionName, undoManager: undoManager)
    }

    func replace(with new: Circuit, actionName: String, undoManager: UndoManager?) {
        let old = circuit
        circuit = new
        undoManager?.registerUndo(withTarget: self) { document in
            document.replace(with: old, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }
}
