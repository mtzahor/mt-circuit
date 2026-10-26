import CircuitCore
import SwiftUI

/// The Equations tab: the circuit's laws and the matrix system the simulator solves, for the
/// current schematic and analysis. They are built from the schematic, not from the last run,
/// so they are shown even when the simulation fails (on a singular matrix, for example).
struct EquationsView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var document: CircuitDocument
    let notation: CircuitEquations.Notation
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let hoveredRow = State<Int?>(initialValue: nil)

    /// Larger systems are listed as equations only: their matrix would be unreadable.
    private static let maxMatrixSize = 30

    var body: some View {
        Group {
            switch Result(catching: { try CircuitEquations(circuit: document.circuit, notation: notation) }) {
            case let .success(equations) where equations.size > 0:
                content(equations)
            case .success:
                placeholder("There is nothing to solve: every element is shorted.")
            case let .failure(error):
                placeholder(error.localizedDescription)
            }
        }
        .onDisappear { editor.highlightedNode = nil }
    }

    private func content(_ equations: CircuitEquations) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text(equations.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // Side by side when there is room; otherwise stacked, each scrolling sideways.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 40) {
                        laws(equations)
                        matrix(equations)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        ScrollView(.horizontal) { laws(equations) }
                        ScrollView(.horizontal) { matrix(equations) }
                    }
                }
                notes(equations)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Sections

    private func laws(_ equations: CircuitEquations) -> some View {
        let labelWidth = equations.rows.map { Self.width(of: $0.label) }.max() ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Circuit equations")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(equations.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(math: row.law)
                                if let note = row.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let solved = row.solvedForm {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("→").foregroundStyle(.tertiary)
                                    Text(math: solved)
                                }
                                .help("The form solved: discretized in time for each time step, or a diode's tangent for each Newton iteration")
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RowHighlight(isOn: hoveredRow.wrappedValue == row.id))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            hover(row.id, in: equations)
                        } else if hoveredRow.wrappedValue == row.id {
                            hover(nil, in: equations)
                        }
                    }
                }
            }
            // Every row as wide as the widest, so the hover highlights line up.
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.enabled)
        }
    }

    private func matrix(_ equations: CircuitEquations) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Matrix form  A·x = b")
            if equations.size <= Self.maxMatrixSize {
                MatrixView(equations: equations, hoveredRow: hoveredRow.wrappedValue) { hover($0, in: equations) }
                    .padding(.horizontal, 6)
            } else {
                Text("The system has \(equations.size) unknowns, too many to show as a matrix.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func notes(_ equations: CircuitEquations) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(equations.notes, id: \.self) { Text($0) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 640, alignment: .leading)
        .textSelection(.enabled)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }

    private func placeholder(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "function")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Highlights the row in both sections, and its net on the schematic for a node row.
    private func hover(_ row: Int?, in equations: CircuitEquations) {
        guard hoveredRow.wrappedValue != row else { return }
        hoveredRow.wrappedValue = row
        editor.highlightedNode = row.flatMap { id in equations.rows.first { $0.id == id }?.node }
    }

    private static func width(of label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return ceil((label as NSString).size(withAttributes: [.font: font]).width)
    }
}

// MARK: - Matrix

/// A·x = b with brackets. Cells are laid out in columns of fixed-height rows, so the brackets
/// span exactly the matrix rows and a hover maps directly to a row.
private struct MatrixView: View {
    let equations: CircuitEquations
    let hoveredRow: Int?
    let onHover: (Int?) -> Void

    private static let rowHeight: CGFloat = 24
    private static let headerHeight: CGFloat = 18

    private var bodyHeight: CGFloat { CGFloat(equations.size) * Self.rowHeight }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            column(alignment: .trailing) { i in
                Text(equations.rows[i].label).foregroundStyle(.secondary)
            }
            bracketed {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<equations.size, id: \.self) { j in
                        column(header: equations.unknowns[j].description) { i in entry(equations.matrix[i][j]) }
                    }
                }
            }
            bracketed {
                column { i in Text(math: equations.unknowns[i]) }
            }
            Text("=")
                .frame(height: bodyHeight)
                .padding(.top, Self.headerHeight)
            bracketed {
                column { i in entry(equations.rhs[i]) }
            }
        }
        .background(alignment: .topLeading) {
            if let hoveredRow {
                RowHighlight(isOn: true)
                    .frame(height: Self.rowHeight)
                    .padding(.horizontal, -6)
                    .offset(y: Self.headerHeight + CGFloat(hoveredRow) * Self.rowHeight)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                let row = Int(floor((location.y - Self.headerHeight) / Self.rowHeight))
                onHover((0..<equations.size).contains(row) ? row : nil)
            case .ended:
                onHover(nil)
            }
        }
    }

    private func column<Cell: View>(
        header: String = "", alignment: HorizontalAlignment = .center, @ViewBuilder cell: @escaping (Int) -> Cell
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(header)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: Self.headerHeight, alignment: .top)
            ForEach(0..<equations.size, id: \.self) { i in
                cell(i).frame(height: Self.rowHeight)
            }
        }
    }

    private func bracketed<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 6) {
            bracket(opening: true)
            content()
            bracket(opening: false)
        }
    }

    private func bracket(opening: Bool) -> some View {
        Bracket(opening: opening)
            .stroke(Color.secondary, lineWidth: 1)
            .frame(width: 4, height: bodyHeight - 4)
            .padding(.top, Self.headerHeight + 2)
    }

    @ViewBuilder
    private func entry(_ text: MathText) -> some View {
        if text.isEmpty {
            Text("0").foregroundStyle(.tertiary)
        } else {
            Text(math: text)
        }
    }
}

private struct Bracket: Shape {
    let opening: Bool

    func path(in rect: CGRect) -> Path {
        let spine = opening ? rect.minX : rect.maxX
        let tip = opening ? rect.maxX : rect.minX
        var path = Path()
        path.move(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: spine, y: rect.minY))
        path.addLine(to: CGPoint(x: spine, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        return path
    }
}

private struct RowHighlight: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

extension Text {
    /// Typesets equation text: unknowns in the accent color, subscripts lowered.
    init(math: MathText) {
        var string = AttributedString()
        for run in math.runs {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .unknown:
                piece.foregroundColor = Color.accentColor
            case .lowered:
                piece.font = Font.caption2
                piece.baselineOffset = -3
            }
            string += piece
        }
        self.init(string)
    }
}
