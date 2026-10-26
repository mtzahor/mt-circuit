import Foundation
import Testing
@testable import CircuitCore

@Suite struct EditingTests {
    private func resistor(at x: Int, _ y: Int, rotation: Int = 0) -> Component {
        Component(kind: .resistor, name: "R1", position: GridPoint(x, y), rotation: rotation)
    }

    @Test func lShapedWire() {
        var circuit = Circuit()
        let ids = circuit.addWire(from: GridPoint(0, 0), to: GridPoint(3, 4), horizontalFirst: true)
        #expect(ids.count == 2)
        #expect(circuit.wires[0].end == GridPoint(3, 0))
        #expect(circuit.wires[1].end == GridPoint(3, 4))
        #expect(circuit.addWire(from: GridPoint(1, 1), to: GridPoint(1, 1), horizontalFirst: true).isEmpty)
    }

    @Test func movingKeepsAttachedWiresConnectedAndOrthogonal() throws {
        // Resistor pins at (0,0) and (4,0); a wire continues right from (4,0) to (8,0).
        let r = resistor(at: 2, 0)
        var circuit = Circuit(components: [r])
        circuit.addWire(from: GridPoint(4, 0), to: GridPoint(8, 0), horizontalFirst: true)

        let moved = circuit.moving([r.id], by: GridPoint(0, 2))
        #expect(moved.components[0].pinPositions == [GridPoint(0, 2), GridPoint(4, 2)])
        // The wire's fixed end stays put; it gets a corner and stays connected to the new pin.
        #expect(moved.wires.count == 2)
        #expect(moved.wires.allSatisfy { $0.start.x == $0.end.x || $0.start.y == $0.end.y })
        #expect(moved.isConnectionPoint(GridPoint(4, 2)))
        #expect(moved.wires.contains { $0.start == GridPoint(8, 0) || $0.end == GridPoint(8, 0) })
    }

    @Test func movingAlongTheWireJustStretchesIt() {
        let r = resistor(at: 2, 0)
        var circuit = Circuit(components: [r])
        circuit.addWire(from: GridPoint(4, 0), to: GridPoint(8, 0), horizontalFirst: true)
        let moved = circuit.moving([r.id], by: GridPoint(-1, 0))
        #expect(moved.wires.count == 1)
        #expect(Set([moved.wires[0].start, moved.wires[0].end]) == [GridPoint(3, 0), GridPoint(8, 0)])
    }

    @Test func rotatingSingleComponentAboutItsOrigin() {
        let r = resistor(at: 5, 5)
        var circuit = Circuit(components: [r])
        circuit.addWire(from: GridPoint(7, 5), to: GridPoint(10, 5), horizontalFirst: true)
        let rotated = circuit.rotating([r.id])
        #expect(rotated.components[0].rotation == 1)
        #expect(rotated.components[0].pinPositions == [GridPoint(5, 3), GridPoint(5, 7)])
        // The wire end attached to pin 2 follows it.
        #expect(rotated.wires[0].start == GridPoint(5, 7))
    }

    @Test func fourRotationsAreIdentity() {
        let r = resistor(at: 1, 1)
        var circuit = Circuit(components: [r, Component(kind: .capacitor, name: "C1", position: GridPoint(7, 1))])
        circuit.addWire(from: GridPoint(3, 1), to: GridPoint(4, 1), horizontalFirst: true)
        circuit.addWire(from: GridPoint(4, 1), to: GridPoint(4, 3), horizontalFirst: true)
        let ids = circuit.allIDs
        var rotated = circuit
        for _ in 0..<4 { rotated = rotated.rotating(ids) }
        #expect(rotated == circuit)
    }

    @Test func pasteRenamesAndOffsets() {
        let r = resistor(at: 0, 0)
        var circuit = Circuit(components: [r])
        let clip = circuit.extracting([r.id])
        let inserted = circuit.paste(clip, offset: GridPoint(2, 2))
        #expect(inserted.count == 1)
        #expect(circuit.components.count == 2)
        #expect(circuit.components[1].name == "R2")
        #expect(circuit.components[1].position == GridPoint(2, 2))
        #expect(circuit.components[1].id != r.id)
    }
}
