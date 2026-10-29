import AppKit
import CircuitCore
import Combine

/// The schematic editor surface. Lives as the document view of an `NSScrollView`, which
/// provides scrolling and pinch / menu zoom; coordinates here are unscaled points.
final class SchematicCanvasView: NSView {
    private let editor: EditorModel
    private var cancellables: Set<AnyCancellable> = []

    // Transient interaction state (kept out of the model so hover doesn't re-render SwiftUI).
    private var cursor: CGPoint?
    private var wireStart: GridPoint?
    private var hoveredWireID: UUID?
    private var drag: Drag = .none
    private var connectivity = Connectivity(circuit: Circuit())
    private var didInitialFit = false

    private enum Drag {
        case none
        case pressOnItem(start: CGPoint, itemID: UUID, additive: Bool)
        case moving(start: CGPoint, offset: GridPoint)
        case marquee(start: CGPoint, current: CGPoint, base: Set<UUID>)

        var isIdle: Bool {
            if case .none = self { return true }
            return false
        }
    }

    private static let minimumSize = CGSize(width: 3200, height: 2400)

    init(editor: EditorModel) {
        self.editor = editor
        super.init(frame: CGRect(origin: .zero, size: Self.minimumSize))
        connectivity = Connectivity(circuit: editor.circuit)
        updateFrameSize()

        editor.document.$circuit
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.circuitDidChange() }
            .store(in: &cancellables)
        editor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &cancellables)
        editor.$tool
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                wireStart = nil
                window?.invalidateCursorRects(for: self)
                needsDisplay = true
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var magnification: CGFloat { enclosingScrollView?.magnification ?? 1 }

    private func circuitDidChange() {
        connectivity = Connectivity(circuit: editor.circuit)
        updateFrameSize()
        needsDisplay = true
    }

    private func updateFrameSize() {
        var size = Self.minimumSize
        for point in editor.circuit.components.map(\.position) + editor.circuit.wires.flatMap({ [$0.start, $0.end] }) {
            let p = SchematicStyle.point(point)
            size.width = max(size.width, p.x + 1200)
            size.height = max(size.height, p.y + 1200)
        }
        if frame.size != size { setFrameSize(size) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didInitialFit else { return }
        didInitialFit = true
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
            self?.zoomToFit(maxMagnification: 1.25)
        }
    }

    // MARK: - Zoom

    func setZoom(_ value: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let visible = scrollView.documentVisibleRect
        scrollView.setMagnification(value, centeredAt: CGPoint(x: visible.midX, y: visible.midY))
    }

    func zoom(by factor: CGFloat) {
        setZoom(magnification * factor)
    }

    /// Fits the circuit in view (or scrolls to the origin when it is empty).
    func zoomToFit(maxMagnification: CGFloat = 2) {
        guard let scrollView = enclosingScrollView else { return }
        guard let content = contentBounds() else {
            scrollView.magnification = 1
            scroll(.zero)
            return
        }
        let target = content.insetBy(dx: -80, dy: -80)
        let viewport = scrollView.contentSize
        let fit = min(viewport.width / target.width, viewport.height / target.height)
        let zoom = min(max(fit, scrollView.minMagnification), maxMagnification)
        scrollView.setMagnification(zoom, centeredAt: CGPoint(x: target.midX, y: target.midY))
    }

    private func contentBounds() -> CGRect? {
        let circuit = editor.circuit
        guard !circuit.isEmpty else { return nil }
        var rect = CGRect.null
        for component in circuit.components { rect = rect.union(SymbolRenderer.bounds(of: component)) }
        for wire in circuit.wires {
            rect = rect.union(CGRect(origin: SchematicStyle.point(wire.start), size: .zero))
            rect = rect.union(CGRect(origin: SchematicStyle.point(wire.end), size: .zero))
        }
        return rect.insetBy(dx: -40, dy: -30)
    }

    // MARK: - Geometry helpers

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func snap(_ p: CGPoint) -> GridPoint {
        GridPoint(Int((p.x / SchematicStyle.grid).rounded()), Int((p.y / SchematicStyle.grid).rounded()))
    }

    private func snappedDelta(from a: CGPoint, to b: CGPoint) -> GridPoint {
        GridPoint(Int(((b.x - a.x) / SchematicStyle.grid).rounded()), Int(((b.y - a.y) / SchematicStyle.grid).rounded()))
    }

    var cursorGridPoint: GridPoint? { cursor.map(snap) }

    /// Topmost component or wire under `p`.
    private func hitTest(item p: CGPoint) -> UUID? {
        let circuit = editor.circuit
        let slop = 4 / magnification
        for component in circuit.components.reversed()
        where SymbolRenderer.bounds(of: component).insetBy(dx: -slop, dy: -slop).contains(p) {
            return component.id
        }
        return hitTest(wire: p)
    }

    private func hitTest(wire p: CGPoint) -> UUID? {
        let tolerance = max(4, 6 / magnification)
        return editor.circuit.wires.last { wire in
            distance(from: p, toSegment: SchematicStyle.point(wire.start), SchematicStyle.point(wire.end)) <= tolerance
        }?.id
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func items(in rect: CGRect) -> Set<UUID> {
        var ids = Set<UUID>()
        for component in editor.circuit.components where rect.contains(SymbolRenderer.bounds(of: component)) {
            ids.insert(component.id)
        }
        for wire in editor.circuit.wires
        where rect.contains(SchematicStyle.point(wire.start)) && rect.contains(SchematicStyle.point(wire.end)) {
            ids.insert(wire.id)
        }
        return ids
    }

    private func wireRoute(to end: GridPoint) -> (start: GridPoint, horizontalFirst: Bool)? {
        guard let start = wireStart else { return nil }
        let horizontalFirst = abs(end.x - start.x) >= abs(end.y - start.y)
        return (start, horizontalFirst)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = location(of: event)
        cursor = p
        switch editor.tool {
        case .select:
            let additive = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            if let id = hitTest(item: p) {
                if additive {
                    if editor.selection.contains(id) { editor.selection.remove(id) } else { editor.selection.insert(id) }
                } else if !editor.selection.contains(id) {
                    editor.selection = [id]
                }
                drag = .pressOnItem(start: p, itemID: id, additive: additive)
            } else {
                let base = additive ? editor.selection : []
                editor.selection = base
                drag = .marquee(start: p, current: p, base: base)
            }

        case .wire:
            let point = snap(p)
            if let (start, horizontalFirst) = wireRoute(to: point) {
                if point == start {
                    wireStart = nil  // clicking the same point again (or double-clicking) ends the wire
                } else {
                    let endsOnConnection = editor.circuit.isConnectionPoint(point)
                    editor.addWire(from: start, to: point, horizontalFirst: horizontalFirst)
                    wireStart = endsOnConnection ? nil : point
                }
            } else {
                wireStart = point
            }

        case let .place(kind):
            editor.place(kind, at: snap(p))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(of: event)
        cursor = p
        switch drag {
        case let .pressOnItem(start, _, additive):
            if !additive, hypot(p.x - start.x, p.y - start.y) > 3 {
                drag = .moving(start: start, offset: snappedDelta(from: start, to: p))
            }
        case let .moving(start, _):
            drag = .moving(start: start, offset: snappedDelta(from: start, to: p))
        case let .marquee(start, _, base):
            drag = .marquee(start: start, current: p, base: base)
            editor.selection = base.union(items(in: rect(start, p)))
        case .none:
            break
        }
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case let .moving(_, offset):
            editor.moveSelection(by: offset)
        case let .pressOnItem(_, id, additive):
            // A plain click on an item in a multi-selection selects just that item.
            if !additive { editor.selection = [id] }
        default:
            break
        }
        drag = .none
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let p = location(of: event)
        cursor = p
        hoveredWireID = editor.tool == .select ? hitTest(wire: p) : nil
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        hoveredWireID = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        switch editor.tool {
        case .place:
            editor.rotate()
        case .wire where wireStart != nil:
            wireStart = nil
            needsDisplay = true
        default:
            super.rightMouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard editor.tool == .select else { return nil }
        if let id = hitTest(item: location(of: event)), !editor.selection.contains(id) {
            editor.selection = [id]
        }
        let menu = NSMenu()
        if let topic = editor.diveInTopic {
            menu.addItem(withTitle: "Dive Into \(topic.title)", action: #selector(diveIn(_:)), keyEquivalent: "")
            menu.addItem(.separator())
        }
        if editor.selection.isEmpty {
            menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Rotate", action: #selector(rotateSelection(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Duplicate", action: #selector(duplicate(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete", action: #selector(delete(_:)), keyEquivalent: "")
        }
        for item in menu.items { item.target = self }
        return menu
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: editor.tool == .select ? .arrow : .crosshair)
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        switch event.keyCode {
        case 51, 117:  // delete, forward delete
            editor.deleteSelection()
            return
        case 53:  // escape
            cancelOperation(nil)
            return
        default:
            break
        }
        guard modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }
        if character == " " {
            editor.rotate()
        } else if let tool = EditorTool.palette.first(where: { $0.key == character }) {
            editor.selectTool(tool)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if wireStart != nil {
            wireStart = nil
        } else if editor.tool != .select {
            editor.selectTool(.select)
        } else {
            editor.selection = []
        }
        needsDisplay = true
    }

    // MARK: - Edit menu actions (responder chain)

    @objc func copy(_ sender: Any?) { editor.copySelection() }
    @objc func cut(_ sender: Any?) { editor.cutSelection() }
    @objc func paste(_ sender: Any?) { editor.paste(at: cursorGridPoint) }
    @objc func delete(_ sender: Any?) { editor.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) { editor.selectAll() }
    @objc func duplicate(_ sender: Any?) { editor.duplicateSelection() }
    @objc func rotateSelection(_ sender: Any?) { editor.rotate() }
    @objc func diveIn(_ sender: Any?) { editor.diveIn() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        SchematicStyle.background.setFill()
        dirtyRect.fill()
        drawGrid(in: dirtyRect, ctx: ctx)

        var circuit = editor.circuit
        var connectivity = self.connectivity
        if case let .moving(_, offset) = drag, offset != .zero {
            circuit = circuit.moving(editor.selection, by: offset)
            connectivity = Connectivity(circuit: circuit)
        }
        let selection = editor.selection

        drawNetHighlight(circuit: circuit, connectivity: connectivity, ctx: ctx)
        SymbolRenderer.drawCircuit(circuit, connectivity: connectivity, in: ctx, highlighted: selection)
        drawOperatingPointAnnotations(ctx: ctx)
        drawToolPreview(circuit: circuit, ctx: ctx)
        drawHoverInfo(connectivity: connectivity, ctx: ctx)

        if case let .marquee(start, current, _) = drag {
            let r = rect(start, current)
            ctx.setFillColor(SchematicStyle.selection.withAlphaComponent(0.08).cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(SchematicStyle.selection.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1 / magnification)
            ctx.stroke(r)
        }
    }

    private func drawGrid(in rect: CGRect, ctx: CGContext) {
        let grid = SchematicStyle.grid
        let step = magnification < 0.5 ? 5 : 1
        let spacing = grid * CGFloat(step)
        let size = max(1.2, 1.4 / magnification)
        var dots: [CGRect] = []
        var x = (rect.minX / spacing).rounded(.down) * spacing
        while x <= rect.maxX {
            var y = (rect.minY / spacing).rounded(.down) * spacing
            while y <= rect.maxY {
                dots.append(CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size))
                y += spacing
            }
            x += spacing
        }
        ctx.setFillColor(SchematicStyle.gridDot.cgColor)
        ctx.fill(dots)
    }

    /// Highlights the hovered net, or the net of the signal hovered in the results list.
    private func drawNetHighlight(circuit: Circuit, connectivity: Connectivity, ctx: CGContext) {
        var wireIDs: [UUID] = []
        if let hovered = hoveredWireID, let net = connectivity.netForWire[hovered] {
            wireIDs = circuit.wires.filter { connectivity.netForWire[$0.id] == net }.map(\.id)
        } else if let node = editor.highlightedNode, let result = editor.result, !editor.resultIsStale {
            wireIDs = circuit.wires.filter { result.netlist.nodeForWire[$0.id] == node }.map(\.id)
        }
        guard !wireIDs.isEmpty else { return }
        let ids = Set(wireIDs)
        ctx.setStrokeColor(SchematicStyle.selection.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(7)
        ctx.setLineCap(.round)
        for wire in circuit.wires where ids.contains(wire.id) {
            ctx.move(to: SchematicStyle.point(wire.start))
            ctx.addLine(to: SchematicStyle.point(wire.end))
        }
        ctx.strokePath()
    }

    /// Voltage tags on each net after a DC operating point analysis.
    private func drawOperatingPointAnnotations(ctx: CGContext) {
        guard drag.isIdle, let result = editor.result, !editor.resultIsStale,
              case let .operatingPoint(op) = result.output else { return }
        let circuit = editor.circuit
        var anchors: [Int: CGPoint] = [:]
        for component in circuit.components where component.kind == .netLabel {
            if let node = result.netlist.node(forComponent: component), anchors[node] == nil {
                let pill = SymbolRenderer.netLabelPill(for: component)
                anchors[node] = CGPoint(x: pill.maxX + 6, y: pill.minY)
            }
        }
        for wire in circuit.wires {
            guard let node = result.netlist.nodeForWire[wire.id], node != 0, anchors[node] == nil else { continue }
            let a = SchematicStyle.point(wire.start), b = SchematicStyle.point(wire.end)
            anchors[node] = CGPoint(x: (a.x + b.x) / 2 + 4, y: (a.y + b.y) / 2 - 20)
        }
        for (node, anchor) in anchors where node != 0 {
            drawBubble(SIFormat.string(op.nodeVoltages[node], unit: "V", significantDigits: 4), at: anchor, ctx: ctx)
        }
    }

    private func drawBubble(_ text: String, at origin: CGPoint, ctx: CGContext, emphasized: Bool = false) {
        let string = NSAttributedString(string: text, attributes: [
            .font: SchematicStyle.annotationFont, .foregroundColor: NSColor.labelColor,
        ])
        let size = string.size()
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 10, height: size.height + 4)
        let path = CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor((emphasized ? NSColor.windowBackgroundColor : SchematicStyle.selection.withAlphaComponent(0.14)).cgColor)
        ctx.fillPath()
        if emphasized {
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
        string.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
    }

    private func drawToolPreview(circuit: Circuit, ctx: CGContext) {
        guard let cursor else { return }
        let point = snap(cursor)
        let ghost = NSColor.labelColor.withAlphaComponent(0.35)
        switch editor.tool {
        case let .place(kind):
            let component = Component(
                kind: kind, name: circuit.nextName(for: kind), position: point, rotation: editor.placementRotation,
                logic: kind == .logicGate ? LogicParameters(function: editor.placementGate) : nil)
            SymbolRenderer.draw(component, in: ctx, color: ghost, showText: false)
        case .wire:
            let p = SchematicStyle.point(point)
            ctx.setStrokeColor(SchematicStyle.wire.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            if let (start, horizontalFirst) = wireRoute(to: point) {
                var preview = Circuit()
                preview.addWire(from: start, to: point, horizontalFirst: horizontalFirst)
                ctx.setLineWidth(SchematicStyle.lineWidth)
                ctx.setLineDash(phase: 0, lengths: [5, 4])
                for wire in preview.wires {
                    ctx.move(to: SchematicStyle.point(wire.start))
                    ctx.addLine(to: SchematicStyle.point(wire.end))
                }
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        case .select:
            break
        }
    }

    /// Net name (and DC voltage, when known) next to the pointer while hovering a wire.
    private func drawHoverInfo(connectivity: Connectivity, ctx: CGContext) {
        guard drag.isIdle, let cursor, let wireID = hoveredWireID else { return }
        var text: String
        if let result = editor.result, !editor.resultIsStale, let node = result.netlist.nodeForWire[wireID] {
            text = node == 0 ? "GND" : result.netlist.nodeNames[node]
            if case let .operatingPoint(op) = result.output {
                text += " = " + SIFormat.string(op.nodeVoltages[node], unit: "V", significantDigits: 4)
            }
        } else if let net = connectivity.netForWire[wireID] {
            text = net == connectivity.groundNet ? "GND" : connectivity.labelForNet[net] ?? "unnamed net"
        } else {
            return
        }
        drawBubble(text, at: CGPoint(x: cursor.x + 14, y: cursor.y + 12), ctx: ctx, emphasized: true)
    }
}

extension SchematicCanvasView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)),
             #selector(duplicate(_:)), #selector(rotateSelection(_:)):
            return !editor.selection.isEmpty
        case #selector(paste(_:)):
            return editor.canPaste
        default:
            return true
        }
    }
}
