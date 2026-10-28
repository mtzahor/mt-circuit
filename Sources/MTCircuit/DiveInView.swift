import AppKit
import CircuitCore
import SwiftUI

/// The topic the Dive In window shows, with back and forward history. There is one Dive In
/// window, shared by every editor window.
@MainActor
final class DiveInModel: ObservableObject {
    static let shared = DiveInModel()
    static let windowID = "dive-in"

    @Published private(set) var topicID = DiveIn.topics[0].id
    @Published private(set) var backStack: [String] = []
    @Published private(set) var forwardStack: [String] = []

    var topic: DiveInTopic { DiveIn.topic(withID: topicID) ?? DiveIn.topics[0] }

    func show(_ id: String) {
        guard id != topicID, DiveIn.topic(withID: id) != nil else { return }
        backStack.append(topicID)
        forwardStack = []
        topicID = id
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(topicID)
        topicID = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(topicID)
        topicID = next
    }
}

extension OpenWindowAction {
    /// Opens the Dive In window, or brings it to the front, showing `topicID` if given.
    @MainActor func diveIn(to topicID: String? = nil) {
        if let topicID { DiveInModel.shared.show(topicID) }
        self(id: DiveInModel.windowID)
    }
}

/// Colors of a schematic figure's regions, matched by the bars beside the sections about them.
enum RegionStyle {
    static let colors: [NSColor] = [.systemBlue, .systemPurple, .systemPink]

    static func color(_ index: Int) -> NSColor { colors[index % colors.count] }
}

// MARK: - Window

struct DiveInView: View {
    @ObservedObject private var model = DiveInModel.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(get: { model.topicID }, set: { $0.map(model.show) })) {
                ForEach(DiveInTopic.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(DiveIn.topics.filter { $0.category == category }) { topic in
                            Label { Text(topic.title) } icon: { TopicIcon(topic: topic) }
                                .tag(topic.id)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            TopicPage(topic: model.topic)
                // A new topic starts at the top, with nothing highlighted.
                .id(model.topicID)
        }
        .navigationTitle("Dive In")
        .navigationSubtitle(model.topic.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: model.goBack) { Label("Back", systemImage: "chevron.left") }
                    .keyboardShortcut("[")
                    .disabled(model.backStack.isEmpty)
                    .help("Back")
                Button(action: model.goForward) { Label("Forward", systemImage: "chevron.right") }
                    .keyboardShortcut("]")
                    .disabled(model.forwardStack.isEmpty)
                    .help("Forward")
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let topic = DiveIn.topic(for: url) else { return .systemAction }
            model.show(topic.id)
            return .handled
        })
    }
}

/// A part's toolbar symbol, or a symbol for a building block.
private struct TopicIcon: View {
    let topic: DiveInTopic

    var body: some View {
        if let kind = ComponentKind.allCases.first(where: { DiveIn.topic(for: $0)?.id == topic.id }) {
            Image(nsImage: SymbolRenderer.icon(for: .place(kind)))
        } else {
            Image(systemName: buildingBlockSymbol)
        }
    }

    private var buildingBlockSymbol: String {
        switch topic.id {
        case "differential-pair": "arrow.left.arrow.right"
        case "current-mirror": "square.on.square"
        case "push-pull": "arrow.up.arrow.down"
        default: "square.stack.3d.down.right"
        }
    }
}

// MARK: - Topic page

private struct TopicPage: View {
    let topic: DiveInTopic
    @Environment(\.newDocument) private var newDocument
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let highlightedRegion = State<Int?>(initialValue: nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                FigureView(figure: topic.figure, highlightedRegion: highlightedRegion.wrappedValue)
                actions
                ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                    SectionView(section: section)
                        .onHover { inside in
                            guard let region = section.region else { return }
                            if inside {
                                highlightedRegion.wrappedValue = region
                            } else if highlightedRegion.wrappedValue == region {
                                highlightedRegion.wrappedValue = nil
                            }
                        }
                }
                related
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topic.category == .parts ? "Inside the part" : "Building block")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(topic.title)
                .font(.largeTitle.weight(.bold))
            Text(topic.headline)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        let lesson = topic.lesson.flatMap(Tutorial.lesson(withID:))
        if topic.circuit != nil || lesson != nil {
            HStack(spacing: 10) {
                if let circuit = topic.circuit {
                    Button {
                        newDocument { CircuitDocument(circuit: circuit) }
                    } label: {
                        Label("Open the Circuit", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Open this circuit in a new window, to simulate and change it")
                }
                if let lesson {
                    Button {
                        newDocument { CircuitDocument(circuit: lesson.startingCircuit) }
                    } label: {
                        Label("Lesson: \(lesson.title)", systemImage: "graduationcap")
                    }
                    .help("Open the tutorial lesson about this part in a new window")
                }
            }
        }
    }

    @ViewBuilder
    private var related: some View {
        let deeper = topic.deeper.compactMap(DiveIn.topic(withID:))
        let containers = DiveIn.containers(of: topic.id)
        if !deeper.isEmpty || !containers.isEmpty {
            Divider()
            if !deeper.isEmpty {
                TopicLinks(title: "Dive deeper", systemImage: "water.waves.and.arrow.down", topics: deeper)
            }
            if !containers.isEmpty {
                TopicLinks(title: "Found inside", systemImage: "arrow.up.right", topics: containers)
            }
        }
    }
}

private struct SectionView: View {
    let section: DiveInSection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let region = section.region {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(nsColor: RegionStyle.color(region)))
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let heading = section.heading {
                    Text(heading)
                        .font(.title3.weight(.semibold))
                }
                LessonText(section.text)
                    .font(.body)
                if let figure = section.figure {
                    FigureView(figure: figure, highlightedRegion: nil)
                        .padding(.top, 4)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Cards that lead to other topics.
private struct TopicLinks: View {
    let title: String
    let systemImage: String
    let topics: [DiveInTopic]
    @ObservedObject private var model = DiveInModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(topics) { topic in
                    Button { model.show(topic.id) } label: {
                        HStack(spacing: 10) {
                            TopicIcon(topic: topic)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title)
                                    .font(.callout.weight(.semibold))
                                Text(topic.headline)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Figures

private struct FigureView: View {
    let figure: DiveInFigure
    let highlightedRegion: Int?

    var body: some View {
        Group {
            switch figure {
            case let .schematic(circuit, regions):
                SchematicFigure(circuit: circuit, regions: regions, highlightedRegion: highlightedRegion)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: SchematicStyle.background))
            case let .illustration(illustration):
                IllustrationView(illustration: illustration)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.05))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// A read-only schematic, scaled down to fit, with its regions outlined and titled.
private struct SchematicFigure: View {
    let circuit: Circuit
    let regions: [SchematicRegion]
    let highlightedRegion: Int?

    var body: some View {
        let size = SchematicFigureView.contentBounds(circuit, regions).size
        Representable(circuit: circuit, regions: regions, highlightedRegion: highlightedRegion)
            .aspectRatio(size, contentMode: .fit)
            .frame(maxWidth: size.width)
            .accessibilityLabel("Schematic")
    }

    private struct Representable: NSViewRepresentable {
        let circuit: Circuit
        let regions: [SchematicRegion]
        let highlightedRegion: Int?

        func makeNSView(context: Context) -> SchematicFigureView {
            SchematicFigureView(circuit: circuit, regions: regions)
        }

        func updateNSView(_ view: SchematicFigureView, context: Context) {
            view.highlightedRegion = highlightedRegion
        }
    }
}

final class SchematicFigureView: NSView {
    private let circuit: Circuit
    private let regions: [SchematicRegion]
    private let connectivity: Connectivity
    var highlightedRegion: Int? {
        didSet { if highlightedRegion != oldValue { needsDisplay = true } }
    }

    private static let regionPadding: CGFloat = 10
    /// Transistors and diodes keep their default parameters in figures, so their values would only add clutter.
    private static let unvalued: Set<ComponentKind> = [.bjt, .mosfet, .diode]
    private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    init(circuit: Circuit, regions: [SchematicRegion]) {
        self.circuit = circuit
        self.regions = regions
        connectivity = Connectivity(circuit: circuit)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// The outline of each region: its parts and their labels, padded.
    private static func outlines(_ circuit: Circuit, _ regions: [SchematicRegion]) -> [CGRect] {
        regions.map { region in
            circuit.components.filter { region.parts.contains($0.name) }
                .reduce(CGRect.null) { $0.union(SymbolRenderer.bounds(of: $1, withText: !unvalued.contains($1.kind))) }
                .insetBy(dx: -regionPadding, dy: -regionPadding)
        }
    }

    private static func title(_ region: SchematicRegion, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: region.title, attributes: [.font: titleFont, .foregroundColor: color])
    }

    /// Everything drawn, with a margin, in schematic coordinates.
    static func contentBounds(_ circuit: Circuit, _ regions: [SchematicRegion]) -> CGRect {
        var rect = SymbolRenderer.bounds(of: circuit, unvalued: unvalued)
        for (region, outline) in zip(regions, outlines(circuit, regions)) {
            let titleHeight = title(region, color: .labelColor).size().height
            rect = rect.union(outline).union(CGRect(x: outline.minX, y: outline.minY - titleHeight - 4, width: 1, height: 1))
        }
        return rect.insetBy(dx: -10, dy: -10)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let content = Self.contentBounds(circuit, regions)
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        ctx.saveGState()
        ctx.translateBy(x: (bounds.width - content.width * scale) / 2, y: (bounds.height - content.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -content.minX, y: -content.minY)
        drawRegions(ctx)
        SymbolRenderer.drawCircuit(circuit, connectivity: connectivity, in: ctx, unvalued: Self.unvalued)
        ctx.restoreGState()
    }

    private func drawRegions(_ ctx: CGContext) {
        for (index, (region, outline)) in zip(regions, Self.outlines(circuit, regions)).enumerated() {
            let color = RegionStyle.color(index)
            let emphasis: CGFloat = switch highlightedRegion {
            case nil: 1
            case index: 2
            default: 0.4
            }
            let path = CGPath(roundedRect: outline, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(color.withAlphaComponent(0.08 * emphasis).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(color.withAlphaComponent(min(1, 0.6 * emphasis)).cgColor)
            ctx.setLineWidth(highlightedRegion == index ? 2 : 1.2)
            ctx.setLineDash(phase: 0, lengths: highlightedRegion == index ? [] : [5, 4])
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            let title = Self.title(region, color: color.withAlphaComponent(min(1, 0.9 * emphasis)))
            title.draw(at: CGPoint(x: outline.minX + 2, y: outline.minY - title.size().height - 2))
        }
    }
}
