// Writes every built-in example circuit to <output dir>/<name>.mtcircuit.
// Built by scripts/export-examples.sh together with the CircuitCore sources.
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Examples")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for example in Examples.all {
    let slug = example.name
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let url = output.appendingPathComponent(slug).appendingPathExtension("mtcircuit")
    try example.circuit.encoded().write(to: url)
    print(url.path)
}
