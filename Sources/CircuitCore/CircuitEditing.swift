import Foundation

/// Geometric editing operations used by the schematic editor.
extension Circuit {
    /// IDs of every component and wire.
    public var allIDs: Set<UUID> {
        Set(components.map(\.id)).union(wires.map(\.id))
    }

    /// Whether something electrical already sits at `point` (a pin, a wire end, or a wire passing through).
    public func isConnectionPoint(_ point: GridPoint) -> Bool {
        components.contains { $0.pinPositions.contains(point) }
            || wires.contains { point.lies(onSegmentFrom: $0.start, to: $0.end) }
    }

    /// Adds a wire from `a` to `b`, routed as an L-shape when the points are not aligned.
    /// Returns the IDs of the new wire segments.
    @discardableResult
    public mutating func addWire(from a: GridPoint, to b: GridPoint, horizontalFirst: Bool) -> [UUID] {
        guard a != b else { return [] }
        var points = [a]
        if a.x != b.x && a.y != b.y {
            points.append(horizontalFirst ? GridPoint(b.x, a.y) : GridPoint(a.x, b.y))
        }
        points.append(b)
        var ids: [UUID] = []
        for (start, end) in zip(points, points.dropFirst()) {
            let wire = Wire(start: start, end: end)
            wires.append(wire)
            ids.append(wire.id)
        }
        return ids
    }

    /// Moves the given components and wires by `offset`.
    ///
    /// Unselected wires attached to moved pins or wire ends stay connected: their attached end
    /// follows, and an axis-aligned wire gets a corner so that it stays orthogonal.
    public func moving(_ ids: Set<UUID>, by offset: GridPoint) -> Circuit {
        guard offset != .zero else { return self }
        var result = self
        var movedPoints = Set<GridPoint>()
        for component in components where ids.contains(component.id) {
            movedPoints.formUnion(component.pinPositions)
        }
        for wire in wires where ids.contains(wire.id) {
            movedPoints.insert(wire.start)
            movedPoints.insert(wire.end)
        }
        for index in result.components.indices where ids.contains(result.components[index].id) {
            result.components[index].position = result.components[index].position + offset
        }

        var newWires: [Wire] = []
        for wire in wires {
            if ids.contains(wire.id) {
                newWires.append(Wire(id: wire.id, start: wire.start + offset, end: wire.end + offset))
                continue
            }
            let startMoves = movedPoints.contains(wire.start)
            let endMoves = movedPoints.contains(wire.end)
            switch (startMoves, endMoves) {
            case (false, false):
                newWires.append(wire)
            case (true, true):
                newWires.append(Wire(id: wire.id, start: wire.start + offset, end: wire.end + offset))
            case (true, false):
                newWires += Self.rubberBand(fixed: wire.end, moved: wire.start, offset: offset, id: wire.id)
            case (false, true):
                newWires += Self.rubberBand(fixed: wire.start, moved: wire.end, offset: offset, id: wire.id)
            }
        }
        result.wires = newWires.filter { $0.start != $0.end }
        return result
    }

    /// Stretches a wire whose `moved` end follows a dragged pin, keeping it orthogonal when possible.
    private static func rubberBand(fixed: GridPoint, moved: GridPoint, offset: GridPoint, id: UUID) -> [Wire] {
        let target = moved + offset
        let horizontal = fixed.y == moved.y && fixed.x != moved.x
        let vertical = fixed.x == moved.x && fixed.y != moved.y
        guard (horizontal || vertical), target.x != fixed.x, target.y != fixed.y else {
            return [Wire(id: id, start: fixed, end: target)]
        }
        // Keep the leg leaving the fixed end in its original direction, then turn toward the target.
        let corner = horizontal ? GridPoint(target.x, fixed.y) : GridPoint(fixed.x, target.y)
        return [Wire(id: id, start: fixed, end: corner), Wire(start: corner, end: target)]
    }

    /// Rotates the selection 90° clockwise. A single component turns about its own origin;
    /// a larger selection turns as a group about its center. Attached wire ends follow.
    public func rotating(_ ids: Set<UUID>) -> Circuit {
        let selectedComponents = components.filter { ids.contains($0.id) }
        let selectedWires = wires.filter { ids.contains($0.id) }
        guard !selectedComponents.isEmpty || !selectedWires.isEmpty else { return self }

        // Pivot in half-grid units so a group turns about its true center; x and y must share
        // parity for rotated grid points to land back on the grid.
        var pivot2: GridPoint
        if selectedComponents.count == 1 && selectedWires.isEmpty {
            pivot2 = GridPoint(selectedComponents[0].position.x * 2, selectedComponents[0].position.y * 2)
        } else {
            let points = selectedComponents.map(\.position) + selectedWires.flatMap { [$0.start, $0.end] }
            let xs = points.map(\.x), ys = points.map(\.y)
            pivot2 = GridPoint(xs.min()! + xs.max()!, ys.min()! + ys.max()!)
            if (pivot2.x + pivot2.y) % 2 != 0 { pivot2.y -= 1 }
        }
        func turn(_ p: GridPoint) -> GridPoint {
            GridPoint((pivot2.x + pivot2.y) / 2 - p.y, p.x + (pivot2.y - pivot2.x) / 2)
        }

        var result = self
        // Where each moved pin / wire end ends up, so attached wires can follow.
        var relocation: [GridPoint: GridPoint] = [:]
        for index in result.components.indices where ids.contains(result.components[index].id) {
            let before = result.components[index].pinPositions
            result.components[index].position = turn(result.components[index].position)
            result.components[index].rotation = (result.components[index].rotation + 1) % 4
            for (old, new) in zip(before, result.components[index].pinPositions) { relocation[old] = new }
        }
        for index in result.wires.indices where ids.contains(result.wires[index].id) {
            let wire = result.wires[index]
            relocation[wire.start] = turn(wire.start)
            relocation[wire.end] = turn(wire.end)
            result.wires[index].start = turn(wire.start)
            result.wires[index].end = turn(wire.end)
        }
        for index in result.wires.indices where !ids.contains(result.wires[index].id) {
            if let new = relocation[result.wires[index].start] { result.wires[index].start = new }
            if let new = relocation[result.wires[index].end] { result.wires[index].end = new }
        }
        result.wires.removeAll { $0.start == $0.end }
        return result
    }

    public func deleting(_ ids: Set<UUID>) -> Circuit {
        var result = self
        result.components.removeAll { ids.contains($0.id) }
        result.wires.removeAll { ids.contains($0.id) }
        return result
    }

    /// The selected items as a standalone circuit (used for copy & paste).
    public func extracting(_ ids: Set<UUID>) -> Circuit {
        Circuit(
            components: components.filter { ids.contains($0.id) },
            wires: wires.filter { ids.contains($0.id) },
            simulation: simulation)
    }

    /// Inserts copies of `clip`'s items shifted by `offset`, with fresh IDs and non-clashing names.
    /// Returns the IDs of the inserted items.
    @discardableResult
    public mutating func paste(_ clip: Circuit, offset: GridPoint) -> Set<UUID> {
        var inserted = Set<UUID>()
        for var component in clip.components {
            component.id = UUID()
            component.position = component.position + offset
            if component.kind != .ground && component.kind != .netLabel
                && components.contains(where: { $0.name == component.name }) {
                component.name = nextName(for: component.kind)
            }
            components.append(component)
            inserted.insert(component.id)
        }
        for wire in clip.wires {
            let copy = Wire(start: wire.start + offset, end: wire.end + offset)
            wires.append(copy)
            inserted.insert(copy.id)
        }
        return inserted
    }
}
