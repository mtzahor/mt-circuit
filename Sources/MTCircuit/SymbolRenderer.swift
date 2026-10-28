import AppKit
import CircuitCore

/// Colors and metrics of the schematic.
enum SchematicStyle {
    static let grid: CGFloat = 20
    static let lineWidth: CGFloat = 1.6
    /// Distance between a two-terminal part's pins and its center, in points.
    static let pinReach: CGFloat = 40

    static let background = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 0.11, alpha: 1) : NSColor(white: 0.995, alpha: 1)
    }
    static let gridDot = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.18)
    }
    static let component = NSColor.labelColor
    static let wire = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.36, green: 0.80, blue: 0.56, alpha: 1)
            : NSColor(srgbRed: 0.05, green: 0.50, blue: 0.29, alpha: 1)
    }
    static let netLabel = NSColor.systemOrange
    static let selection = NSColor.controlAccentColor
    static let unconnected = NSColor.systemRed

    static let nameFont = NSFont.systemFont(ofSize: 10.5, weight: .medium)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let annotationFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    static func point(_ p: GridPoint) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * grid, y: CGFloat(p.y) * grid)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Draws schematic symbols with Core Graphics in a flipped (y-down) context.
enum SymbolRenderer {
    /// Half-thickness of the symbol body perpendicular to its pins; used for label placement.
    static func bodyHalfHeight(_ kind: ComponentKind) -> CGFloat {
        switch kind {
        case .voltageSource, .currentSource: 20
        case .opAmp: 32
        case .capacitor: 14
        case .ground: 22
        default: 10
        }
    }

    /// Body outline in local (unrotated) coordinates, for hit testing.
    static func localBounds(_ kind: ComponentKind) -> CGRect {
        switch kind {
        case .resistor: CGRect(x: -40, y: -10, width: 80, height: 20)
        case .capacitor: CGRect(x: -40, y: -16, width: 80, height: 32)
        case .inductor: CGRect(x: -40, y: -11, width: 80, height: 16)
        case .diode: CGRect(x: -40, y: -12, width: 80, height: 24)
        case .bjt, .mosfet: CGRect(x: -40, y: -40, width: 64, height: 80)
        case .voltageSource, .currentSource: CGRect(x: -40, y: -22, width: 80, height: 44)
        case .opAmp: CGRect(x: -40, y: -34, width: 80, height: 68)
        case .ground: CGRect(x: -14, y: -3, width: 28, height: 28)
        case .netLabel: CGRect(x: -5, y: -5, width: 10, height: 10)
        }
    }

    /// Axis-aligned bounds of a component's body in document coordinates.
    static func bounds(of component: Component) -> CGRect {
        let local = localBounds(component.kind)
        let corners = [
            CGPoint(x: local.minX, y: local.minY), CGPoint(x: local.maxX, y: local.minY),
            CGPoint(x: local.minX, y: local.maxY), CGPoint(x: local.maxX, y: local.maxY),
        ].map { rotate($0, by: component.rotation) }
        let origin = SchematicStyle.point(component.position)
        var rect = CGRect(
            x: corners.map(\.x).min()!, y: corners.map(\.y).min()!,
            width: 0, height: 0)
        rect.size = CGSize(width: corners.map(\.x).max()! - rect.minX, height: corners.map(\.y).max()! - rect.minY)
        rect = rect.offsetBy(dx: origin.x, dy: origin.y)
        if component.kind == .netLabel { rect = rect.union(netLabelPill(for: component)) }
        return rect
    }

    static func rotate(_ p: CGPoint, by quarterTurns: Int) -> CGPoint {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: CGPoint(x: -p.y, y: p.x)
        case 2: CGPoint(x: -p.x, y: -p.y)
        case 3: CGPoint(x: p.y, y: -p.x)
        default: p
        }
    }

    // MARK: - Circuits

    /// Draws a circuit's wires and components, junction dots, and red squares on unconnected pins.
    /// Items in `highlighted` are drawn in the selection color; parts of the `unvalued` kinds show only their names.
    static func drawCircuit(
        _ circuit: Circuit, connectivity: Connectivity, in ctx: CGContext, highlighted: Set<UUID> = [], unvalued: Set<ComponentKind> = []
    ) {
        ctx.setLineCap(.round)
        ctx.setLineWidth(SchematicStyle.lineWidth)
        for wire in circuit.wires {
            let color = highlighted.contains(wire.id) ? SchematicStyle.selection : SchematicStyle.wire
            ctx.setStrokeColor(color.cgColor)
            ctx.move(to: SchematicStyle.point(wire.start))
            ctx.addLine(to: SchematicStyle.point(wire.end))
            ctx.strokePath()
        }

        for component in circuit.components {
            let color = highlighted.contains(component.id) ? SchematicStyle.selection : SchematicStyle.component
            draw(component, in: ctx, color: color, showsValue: !unvalued.contains(component.kind))
        }

        let pins = Set(circuit.components.filter { $0.kind != .netLabel }.flatMap(\.pinPositions))
        for (point, count) in connectivity.connectionCount {
            let p = SchematicStyle.point(point)
            if count >= 3 {
                ctx.setFillColor(SchematicStyle.wire.cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            } else if count == 1, pins.contains(point) {
                ctx.setStrokeColor(SchematicStyle.unconnected.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            }
        }
    }

    /// Bounds of everything `drawCircuit` draws, including part names and values.
    static func bounds(of circuit: Circuit, unvalued: Set<ComponentKind> = []) -> CGRect {
        var rect = CGRect.null
        for component in circuit.components {
            rect = rect.union(bounds(of: component, withText: !unvalued.contains(component.kind)))
        }
        for wire in circuit.wires {
            rect = rect.union(CGRect(origin: SchematicStyle.point(wire.start), size: .zero))
            rect = rect.union(CGRect(origin: SchematicStyle.point(wire.end), size: .zero))
        }
        return rect
    }

    // MARK: - Components

    /// Draws a component with its labels.
    static func draw(_ component: Component, in ctx: CGContext, color: NSColor, showText: Bool = true, showsValue: Bool = true) {
        let origin = SchematicStyle.point(component.position)
        if component.kind == .netLabel {
            drawNetLabel(component, in: ctx, color: color)
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.rotate(by: CGFloat(component.rotation) * .pi / 2)
        drawBody(component.kind, in: ctx, color: color, polarity: component.transistor?.polarity ?? .n)
        ctx.restoreGState()

        if component.kind.isSource {
            drawSourceDecorations(component, at: origin, in: ctx, color: color)
        }
        if component.kind == .opAmp {
            drawOpAmpDecorations(component, at: origin, in: ctx, color: color)
        }
        if showText {
            for (text, point) in textLayout(for: component, showsValue: showsValue) { text.draw(at: point) }
        }
    }

    /// Strokes a symbol body in local coordinates (pins at (±40, 0), or (0, 0) for ground;
    /// an op-amp's inputs are at (−40, ±20) and its output at (40, 0); a transistor's control pin is
    /// at (−40, 0) and its others at (20, ±40)). P-type transistors are drawn upside down.
    static func drawBody(
        _ kind: ComponentKind, in ctx: CGContext, color: NSColor, lineWidth: CGFloat = SchematicStyle.lineWidth,
        polarity: TransistorParameters.Polarity = .n
    ) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
        }

        switch kind {
        case .resistor:
            ctx.move(to: CGPoint(x: -40, y: 0))
            ctx.addLine(to: CGPoint(x: -20, y: 0))
            for i in 0..<6 {
                let x = -20 + CGFloat(2 * i + 1) * 40 / 12
                ctx.addLine(to: CGPoint(x: x, y: i.isMultiple(of: 2) ? -7 : 7))
            }
            ctx.addLine(to: CGPoint(x: 20, y: 0))
            ctx.addLine(to: CGPoint(x: 40, y: 0))
            ctx.strokePath()

        case .capacitor:
            line(-40, 0, -5, 0)
            line(5, 0, 40, 0)
            ctx.strokePath()
            ctx.setLineWidth(lineWidth * 1.6)
            line(-5, -14, -5, 14)
            line(5, -14, 5, 14)
            ctx.strokePath()

        case .inductor:
            ctx.move(to: CGPoint(x: -40, y: 0))
            ctx.addLine(to: CGPoint(x: -24, y: 0))
            for i in 0..<4 {
                let x0 = -24 + CGFloat(i) * 12
                ctx.addCurve(
                    to: CGPoint(x: x0 + 12, y: 0),
                    control1: CGPoint(x: x0, y: -10),
                    control2: CGPoint(x: x0 + 12, y: -10))
            }
            ctx.addLine(to: CGPoint(x: 40, y: 0))
            ctx.strokePath()

        case .voltageSource, .currentSource:
            line(-40, 0, -20, 0)
            line(20, 0, 40, 0)
            ctx.strokePath()
            ctx.strokeEllipse(in: CGRect(x: -20, y: -20, width: 40, height: 40))
            if kind == .currentSource {
                // Arrow points from pin 1 to pin 2: the direction of positive current inside the source.
                line(-11, 0, 11, 0)
                line(11, 0, 5, -5)
                line(11, 0, 5, 5)
                ctx.strokePath()
            }

        case .diode:
            // Current flows from the anode (pin 1) along the arrow into the cathode bar (pin 2).
            line(-40, 0, -10, 0)
            line(10, 0, 40, 0)
            line(10, -10, 10, 10)
            ctx.strokePath()
            ctx.move(to: CGPoint(x: -10, y: -10))
            ctx.addLine(to: CGPoint(x: 10, y: 0))
            ctx.addLine(to: CGPoint(x: -10, y: 10))
            ctx.closePath()
            ctx.strokePath()

        case .bjt, .mosfet:
            drawTransistor(kind, polarity: polarity, in: ctx, lineWidth: lineWidth)

        case .opAmp:
            line(-40, -20, -28, -20)
            line(-40, 20, -28, 20)
            line(32, 0, 40, 0)
            ctx.strokePath()
            ctx.move(to: CGPoint(x: -28, y: -32))
            ctx.addLine(to: CGPoint(x: 32, y: 0))
            ctx.addLine(to: CGPoint(x: -28, y: 32))
            ctx.closePath()
            ctx.strokePath()

        case .ground:
            line(0, 0, 0, 12)
            line(-12, 12, 12, 12)
            line(-7.5, 17, 7.5, 17)
            line(-3, 22, 3, 22)
            ctx.strokePath()

        case .netLabel:
            ctx.fillEllipse(in: CGRect(x: -2.5, y: -2.5, width: 5, height: 5))
        }
    }

    /// Polarity marks and waveform glyph, drawn upright regardless of rotation.
    private static func drawSourceDecorations(_ component: Component, at origin: CGPoint, in ctx: CGContext, color: NSColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        func at(_ local: CGPoint) -> CGPoint {
            let r = rotate(local, by: component.rotation)
            return CGPoint(x: origin.x + r.x, y: origin.y + r.y)
        }
        let shape = component.waveform.shape
        if component.kind == .voltageSource {
            let reach: CGFloat = shape == .dc ? 10 : 13
            let plus = at(CGPoint(x: -reach, y: 0)), minus = at(CGPoint(x: reach, y: 0))
            ctx.move(to: CGPoint(x: plus.x - 3.5, y: plus.y)); ctx.addLine(to: CGPoint(x: plus.x + 3.5, y: plus.y))
            ctx.move(to: CGPoint(x: plus.x, y: plus.y - 3.5)); ctx.addLine(to: CGPoint(x: plus.x, y: plus.y + 3.5))
            ctx.move(to: CGPoint(x: minus.x - 3.5, y: minus.y)); ctx.addLine(to: CGPoint(x: minus.x + 3.5, y: minus.y))
            ctx.strokePath()
        }
        if shape != .dc {
            // Small waveform glyph; offset off-center for current sources so it does not cover the arrow.
            let center = component.kind == .currentSource ? at(CGPoint(x: 0, y: -26)) : origin
            drawWaveformGlyph(shape, center: center, in: ctx)
        }
        ctx.restoreGState()
    }

    /// A BJT or MOSFET in N-type orientation: control pin on the left, collector or drain on top,
    /// emitter or source at the bottom with the arrow. A P-type device is the mirror image, with the
    /// arrow pointing in instead of out.
    private static func drawTransistor(
        _ kind: ComponentKind, polarity: TransistorParameters.Polarity, in ctx: CGContext, lineWidth: CGFloat
    ) {
        ctx.saveGState()
        if polarity == .p { ctx.scaleBy(x: 1, y: -1) }
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            ctx.move(to: CGPoint(x: x1, y: y1))
            ctx.addLine(to: CGPoint(x: x2, y: y2))
        }
        /// A filled arrowhead with its tip at `tip`, pointing along `direction`.
        func arrow(tip: CGPoint, direction: CGVector) {
            let length = hypot(direction.dx, direction.dy)
            let u = CGVector(dx: direction.dx / length, dy: direction.dy / length)
            let base = CGPoint(x: tip.x - 8 * u.dx, y: tip.y - 8 * u.dy)
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: base.x - 4 * u.dy, y: base.y + 4 * u.dx))
            ctx.addLine(to: CGPoint(x: base.x + 4 * u.dy, y: base.y - 4 * u.dx))
            ctx.closePath()
            ctx.fillPath()
        }
        let outward: CGFloat = polarity == .n ? 1 : -1
        if kind == .bjt {
            line(-40, 0, -12, 0)
            line(-12, -7, 20, -24)
            line(20, -24, 20, -40)
            line(-12, 7, 20, 24)
            line(20, 24, 20, 40)
            ctx.strokePath()
            ctx.setLineWidth(lineWidth * 1.6)
            line(-12, -16, -12, 16)
            ctx.strokePath()
            // On the emitter: out of the transistor for NPN, into it for PNP.
            let emitter = CGVector(dx: 32, dy: 17)
            let t: CGFloat = polarity == .n ? 0.85 : 0.35
            arrow(tip: CGPoint(x: -12 + t * emitter.dx, y: 7 + t * emitter.dy),
                  direction: CGVector(dx: outward * emitter.dx, dy: outward * emitter.dy))
        } else {
            line(-40, 0, -14, 0)
            line(-14, -16, -14, 16)
            line(-7, -12, 20, -12)
            line(20, -12, 20, -40)
            line(-7, 12, 20, 12)
            line(20, 12, 20, 40)
            ctx.strokePath()
            ctx.setLineWidth(lineWidth * 1.6)
            line(-7, -18, -7, 18)
            ctx.strokePath()
            // On the source: out of the channel for N-channel, into it for P-channel.
            arrow(tip: CGPoint(x: polarity == .n ? 12 : -1, y: 12), direction: CGVector(dx: outward, dy: 0))
        }
        ctx.restoreGState()
    }

    /// The − and + marks at the inputs, drawn upright so the minus stays horizontal when rotated.
    private static func drawOpAmpDecorations(_ component: Component, at origin: CGPoint, in ctx: CGContext, color: NSColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        func at(_ local: CGPoint) -> CGPoint {
            let r = rotate(local, by: component.rotation)
            return CGPoint(x: origin.x + r.x, y: origin.y + r.y)
        }
        let minus = at(CGPoint(x: -19, y: -20)), plus = at(CGPoint(x: -19, y: 20))
        ctx.move(to: CGPoint(x: minus.x - 4, y: minus.y)); ctx.addLine(to: CGPoint(x: minus.x + 4, y: minus.y))
        ctx.move(to: CGPoint(x: plus.x - 4, y: plus.y)); ctx.addLine(to: CGPoint(x: plus.x + 4, y: plus.y))
        ctx.move(to: CGPoint(x: plus.x, y: plus.y - 4)); ctx.addLine(to: CGPoint(x: plus.x, y: plus.y + 4))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawWaveformGlyph(_ shape: SourceWaveform.Shape, center c: CGPoint, in ctx: CGContext) {
        let w: CGFloat = 5.5, h: CGFloat = 3.5
        switch shape {
        case .dc:
            return
        case .sine:
            ctx.move(to: CGPoint(x: c.x - w, y: c.y))
            ctx.addCurve(to: CGPoint(x: c.x, y: c.y), control1: CGPoint(x: c.x - w * 0.6, y: c.y - h * 2), control2: CGPoint(x: c.x - w * 0.4, y: c.y - h * 2))
            ctx.addCurve(to: CGPoint(x: c.x + w, y: c.y), control1: CGPoint(x: c.x + w * 0.4, y: c.y + h * 2), control2: CGPoint(x: c.x + w * 0.6, y: c.y + h * 2))
        case .step:
            ctx.move(to: CGPoint(x: c.x - w, y: c.y + h))
            ctx.addLine(to: CGPoint(x: c.x - 1, y: c.y + h))
            ctx.addLine(to: CGPoint(x: c.x - 1, y: c.y - h))
            ctx.addLine(to: CGPoint(x: c.x + w, y: c.y - h))
        case .pulse:
            ctx.move(to: CGPoint(x: c.x - w, y: c.y + h))
            ctx.addLine(to: CGPoint(x: c.x - 2.5, y: c.y + h))
            ctx.addLine(to: CGPoint(x: c.x - 2.5, y: c.y - h))
            ctx.addLine(to: CGPoint(x: c.x + 2.5, y: c.y - h))
            ctx.addLine(to: CGPoint(x: c.x + 2.5, y: c.y + h))
            ctx.addLine(to: CGPoint(x: c.x + w, y: c.y + h))
        }
        ctx.strokePath()
    }

    /// Bounds of a component's body and its name, and its value if `showsValue`.
    static func bounds(of component: Component, withText showsValue: Bool) -> CGRect {
        textLayout(for: component, showsValue: showsValue).reduce(bounds(of: component)) { rect, text in
            rect.union(CGRect(origin: text.1, size: text.0.size()))
        }
    }

    /// A component's name, and its value if `showsValue`, each with the point to draw it at.
    private static func textLayout(for component: Component, showsValue: Bool = true) -> [(NSAttributedString, CGPoint)] {
        Array(nameAndValueLayout(for: component).prefix(showsValue ? 2 : 1))
    }

    /// A component's name and value, each with the point to draw it at; none for grounds and net labels.
    private static func nameAndValueLayout(for component: Component) -> [(NSAttributedString, CGPoint)] {
        guard component.kind.hasValue else { return [] }
        let origin = SchematicStyle.point(component.position)
        let name = NSAttributedString(string: component.name, attributes: [
            .font: SchematicStyle.nameFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let value = NSAttributedString(string: component.valueDescription, attributes: [
            .font: SchematicStyle.valueFont, .foregroundColor: NSColor.labelColor,
        ])
        if component.kind.isTransistor {
            // Beside the symbol, clear of the leads that run to its top and bottom pins.
            let x = bounds(of: component).maxX + 4
            return [(name, CGPoint(x: x, y: origin.y - name.size().height)), (value, CGPoint(x: x, y: origin.y))]
        }
        let gap = bodyHalfHeight(component.kind) + 4
        if component.rotation.isMultiple(of: 2) {
            let nameSize = name.size(), valueSize = value.size()
            return [
                (name, CGPoint(x: origin.x - nameSize.width / 2, y: origin.y - gap - nameSize.height)),
                (value, CGPoint(x: origin.x - valueSize.width / 2, y: origin.y + gap)),
            ]
        }
        let x = origin.x + gap + 2
        return [(name, CGPoint(x: x, y: origin.y - name.size().height)), (value, CGPoint(x: x, y: origin.y))]
    }

    // MARK: - Net labels

    private static func netLabelText(_ component: Component, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: component.name.isEmpty ? "?" : component.name, attributes: [
            .font: SchematicStyle.labelFont, .foregroundColor: color,
        ])
    }

    /// The flag shape of a net label, above and to the right of its pin.
    static func netLabelPill(for component: Component) -> CGRect {
        let origin = SchematicStyle.point(component.position)
        let size = netLabelText(component, color: .labelColor).size()
        return CGRect(x: origin.x + 4, y: origin.y - 12 - size.height - 4, width: size.width + 12, height: size.height + 4)
    }

    private static func drawNetLabel(_ component: Component, in ctx: CGContext, color: NSColor) {
        let origin = SchematicStyle.point(component.position)
        let isDefaultColor = color == SchematicStyle.component
        let tint = isDefaultColor ? SchematicStyle.netLabel : color
        let pill = netLabelPill(for: component)
        ctx.saveGState()
        ctx.setStrokeColor(tint.cgColor)
        ctx.setFillColor(tint.cgColor)
        ctx.setLineWidth(1.4)
        ctx.fillEllipse(in: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6))
        ctx.move(to: origin)
        ctx.addLine(to: CGPoint(x: pill.minX + 6, y: pill.maxY))
        ctx.strokePath()
        let path = CGPath(roundedRect: pill, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.setFillColor(tint.withAlphaComponent(0.12).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
        netLabelText(component, color: NSColor.labelColor).draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2))
    }

    // MARK: - Toolbar icons

    private static var iconCache: [String: NSImage] = [:]

    /// Template image of a tool for the toolbar.
    static func icon(for tool: EditorTool) -> NSImage {
        if let cached = iconCache[tool.id] { return cached }
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            switch tool {
            case .select:
                return false
            case .wire:
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1.6)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: -10, y: 6))
                ctx.addLine(to: CGPoint(x: 0, y: 6))
                ctx.addLine(to: CGPoint(x: 0, y: -6))
                ctx.addLine(to: CGPoint(x: 10, y: -6))
                ctx.strokePath()
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillEllipse(in: CGRect(x: -12, y: 4, width: 4, height: 4))
                ctx.fillEllipse(in: CGRect(x: 8, y: -8, width: 4, height: 4))
            case .place(.ground):
                ctx.translateBy(x: 0, y: -8)
                ctx.scaleBy(x: 0.7, y: 0.7)
                drawBody(.ground, in: ctx, color: .black, lineWidth: 2.2)
            case .place(.netLabel):
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1.5)
                let tag = CGMutablePath()
                tag.move(to: CGPoint(x: -10, y: -5))
                tag.addLine(to: CGPoint(x: 5, y: -5))
                tag.addLine(to: CGPoint(x: 10, y: 0))
                tag.addLine(to: CGPoint(x: 5, y: 5))
                tag.addLine(to: CGPoint(x: -10, y: 5))
                tag.closeSubpath()
                ctx.addPath(tag)
                ctx.strokePath()
            case let .place(kind):
                let scale: CGFloat = kind.isSource ? 0.36 : kind == .opAmp ? 0.26 : kind.isTransistor ? 0.22 : 0.3
                ctx.scaleBy(x: scale, y: scale)
                drawBody(kind, in: ctx, color: .black, lineWidth: 1.5 / scale)
                if kind == .voltageSource {
                    ctx.setLineWidth(1.2 / scale)
                    ctx.move(to: CGPoint(x: -14, y: 0)); ctx.addLine(to: CGPoint(x: -4, y: 0))
                    ctx.move(to: CGPoint(x: -9, y: -5)); ctx.addLine(to: CGPoint(x: -9, y: 5))
                    ctx.move(to: CGPoint(x: 4, y: 0)); ctx.addLine(to: CGPoint(x: 14, y: 0))
                    ctx.strokePath()
                }
            }
            return true
        }
        image.isTemplate = true
        iconCache[tool.id] = image
        return image
    }
}
