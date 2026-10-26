import CircuitCore
import SwiftUI

/// A text field for a number with SI prefixes ("4.7k", "10u"). Commits on Return or when focus
/// leaves; invalid input is shown in red and not committed.
struct SIField: View {
    let label: String
    let unit: String
    let value: Double
    /// Shown (and committed as 0) when the field is empty, e.g. "auto".
    var emptyPlaceholder: String?
    var range: ClosedRange<Double>?
    /// Fixed width of the text box; nil lets it fill the available space.
    var fieldWidth: CGFloat?
    let onCommit: (Double) -> Void

    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let textState = State(initialValue: "")
    private let invalidState = State(initialValue: false)
    @FocusState private var isFocused: Bool

    private var text: String {
        get { textState.wrappedValue }
        nonmutating set { textState.wrappedValue = newValue }
    }
    private var isInvalid: Bool {
        get { invalidState.wrappedValue }
        nonmutating set { invalidState.wrappedValue = newValue }
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, text: textState.projectedValue, prompt: emptyPlaceholder.map { Text($0) })
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .frame(minWidth: fieldWidth ?? 60, maxWidth: fieldWidth ?? .infinity)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, alignment: .leading)
                }
            }
        }
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { text = formatted(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
        .help(isInvalid ? "Enter a number, optionally with an SI prefix: 4.7k, 10u, 100n, 1meg" : "")
    }

    private func formatted(_ v: Double) -> String {
        if emptyPlaceholder != nil && v == 0 { return "" }
        return SIFormat.compact(v, significantDigits: 6)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parsed: Double? = trimmed.isEmpty && emptyPlaceholder != nil ? 0 : SIFormat.parse(trimmed)
        guard let parsed, range.map({ $0.contains(parsed) }) ?? true else {
            isInvalid = true
            return
        }
        isInvalid = false
        if parsed != value { onCommit(parsed) }
        text = formatted(parsed)
    }
}

/// A plain text field that commits on Return or focus loss.
struct CommitTextField: View {
    let label: String
    let value: String
    let onCommit: (String) -> Void

    private let textState = State(initialValue: "")
    @FocusState private var isFocused: Bool

    private var text: String {
        get { textState.wrappedValue }
        nonmutating set { textState.wrappedValue = newValue }
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: textState.projectedValue)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(commit)
        }
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in if !isFocused { text = newValue } }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            text = value
            return
        }
        if trimmed != value { onCommit(trimmed) }
    }
}
