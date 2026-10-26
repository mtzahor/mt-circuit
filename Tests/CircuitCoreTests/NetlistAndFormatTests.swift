import Foundation
import Testing
@testable import CircuitCore

@Suite struct SIFormatTests {
    @Test(arguments: [
        ("1000", 1000.0), ("4.7k", 4700), ("4k7", 4700), ("10uF", 10e-6), ("100 nF", 100e-9),
        ("2.2µ", 2.2e-6), ("2.2μH", 2.2e-6), ("1meg", 1e6), ("1MEG", 1e6), ("1M", 1e6), ("1m", 1e-3),
        ("1MHz", 1e6), ("10ms", 10e-3), ("1e-3", 1e-3), ("-5V", -5), ("5 V", 5), ("1fF", 1e-15),
        ("10F", 10), ("47 kΩ", 47e3), ("1kohm", 1e3), (".5", 0.5), ("3p3", 3.3e-12), ("1E6", 1e6),
    ])
    func parses(text: String, expected: Double) throws {
        let value = try #require(SIFormat.parse(text))
        #expect(abs(value - expected) <= abs(expected) * 1e-12)
    }

    @Test(arguments: ["", "abc", "k", "1 2", "1x", "5Vx"])
    func rejects(text: String) {
        #expect(SIFormat.parse(text) == nil)
    }

    @Test func formats() {
        #expect(SIFormat.string(4700, unit: "Ω") == "4.7 kΩ")
        #expect(SIFormat.string(1e-6, unit: "F") == "1 µF")
        #expect(SIFormat.string(0.5, unit: "V") == "500 mV")
        #expect(SIFormat.string(5, unit: "V") == "5 V")
        #expect(SIFormat.string(0, unit: "A") == "0 A")
        #expect(SIFormat.string(-2.5e-3, unit: "A") == "-2.5 mA")
        #expect(SIFormat.string(999.97, unit: "Hz") == "1 kHz")
        #expect(SIFormat.string(123456, unit: "Hz") == "123 kHz")
        #expect(SIFormat.compact(4700) == "4.7k")
        #expect(SIFormat.compact(1e-6) == "1µ")
        #expect(SIFormat.compact(12.5) == "12.5")
    }

    @Test func roundTrips() throws {
        for value in [1.0, 4.7e3, 2.2e-9, 1e6, 0.033, 15e-3] {
            let parsed = try #require(SIFormat.parse(SIFormat.compact(value)))
            #expect(abs(parsed - value) <= value * 1e-9)
        }
    }
}

@Suite struct NetlistTests {
    @Test func requiresGround() {
        let circuit = Circuit(components: [Component(kind: .resistor, name: "R1", position: .zero)])
        #expect(throws: NetlistError.noGround) { try Netlist(circuit: circuit) }
    }

    @Test func rejectsNonPositiveValues() {
        let circuit = Circuit(components: [
            Component(kind: .resistor, name: "R1", position: GridPoint(2, 0), value: 0),
            Component(kind: .ground, name: "GND", position: .zero),
        ])
        #expect(throws: NetlistError.self) { try Netlist(circuit: circuit) }
    }

    @Test func wiresJoinAtEndpointsAndTJunctions() throws {
        // R1 from (0,0) to (4,0); R2 vertical from (2,2) to (2,6).
        // Wire (4,0)-(10,0) and a wire from the middle of it, (6,0)-(6,2), plus a wire to R2's top.
        var circuit = Circuit()
        circuit.components = [
            Component(kind: .resistor, name: "R1", position: GridPoint(2, 0), rotation: 0),
            Component(kind: .resistor, name: "R2", position: GridPoint(6, 4), rotation: 1),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(6, 6)),
        ]
        circuit.wires = [
            Wire(start: GridPoint(4, 0), end: GridPoint(10, 0)),
            Wire(start: GridPoint(6, 0), end: GridPoint(6, 2)),
        ]
        let netlist = try Netlist(circuit: circuit)
        let r1 = netlist.elements.first { $0.name == "R1" }!
        let r2 = netlist.elements.first { $0.name == "R2" }!
        #expect(r1.nodeA == 0)
        #expect(r2.nodeB == 0)
        #expect(r1.nodeB == r2.nodeA)
        #expect(r1.nodeB != 0)
        #expect(netlist.nodeCount == 2)
    }

    @Test func connectivityCountsJunctionsWithoutGround() {
        // A T: horizontal wire (0,0)-(8,0) with a branch from its middle down to a resistor pin.
        var circuit = Circuit(components: [Component(kind: .resistor, name: "R1", position: GridPoint(4, 4), rotation: 1)])
        circuit.wires = [Wire(start: GridPoint(0, 0), end: GridPoint(8, 0)), Wire(start: GridPoint(4, 0), end: GridPoint(4, 2))]
        let connectivity = Connectivity(circuit: circuit)
        #expect(connectivity.groundNet == nil)
        #expect(connectivity.connectionCount[GridPoint(4, 0)] == 3)
        #expect(connectivity.connectionCount[GridPoint(4, 6)] == 1)  // R1's unconnected bottom pin
        #expect(connectivity.netAtPoint[GridPoint(8, 0)] == connectivity.netAtPoint[GridPoint(4, 2)])
    }

    @Test func netLabelsConnectAndNameNets() throws {
        var circuit = Circuit()
        circuit.components = [
            Component(kind: .resistor, name: "R1", position: GridPoint(2, 0), rotation: 0),
            Component(kind: .resistor, name: "R2", position: GridPoint(22, 0), rotation: 0),
            Component(kind: .netLabel, name: "vout", position: GridPoint(4, 0)),
            Component(kind: .netLabel, name: "vout", position: GridPoint(20, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(24, 0)),
        ]
        let netlist = try Netlist(circuit: circuit)
        #expect(netlist.nodeNames == ["0", "vout"])
        #expect(netlist.warnings.isEmpty)
    }

    @Test func shortedVoltageSourceIsAnError() {
        var circuit = Circuit()
        circuit.components = [
            Component(kind: .voltageSource, name: "V1", position: GridPoint(0, 2)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 4)),
        ]
        circuit.wires = [Wire(start: GridPoint(0, 0), end: GridPoint(0, 4))]
        #expect(throws: NetlistError.shortedSource(component: "V1")) { try Netlist(circuit: circuit) }
    }

    @Test func warnsAboutUnconnectedPins() throws {
        let circuit = Circuit(components: [
            Component(kind: .resistor, name: "R1", position: GridPoint(2, 0), rotation: 0),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 0)),
        ])
        let netlist = try Netlist(circuit: circuit)
        #expect(netlist.warnings.contains { $0.contains("R1") })
    }

    @Test func opAmpPinsFollowRotation() {
        let opAmp = Component(kind: .opAmp, name: "U1", position: GridPoint(6, 1), rotation: 0)
        // + input bottom left, − input top left, output on the right.
        #expect(opAmp.pinPositions == [GridPoint(4, 2), GridPoint(4, 0), GridPoint(8, 1)])
        var turned = opAmp
        turned.rotation = 1
        #expect(turned.pinPositions == [GridPoint(5, -1), GridPoint(7, -1), GridPoint(6, 3)])
    }

    @Test func opAmpNodesAreInPinOrder() throws {
        // Voltage follower: + on "in", − and output on "out".
        let circuit = Circuit(components: [
            Component(kind: .opAmp, name: "U1", position: GridPoint(6, 1)),
            Component(kind: .netLabel, name: "in", position: GridPoint(4, 2)),
            Component(kind: .netLabel, name: "out", position: GridPoint(4, 0)),
            Component(kind: .netLabel, name: "out", position: GridPoint(8, 1)),
            Component(kind: .voltageSource, name: "V1", position: GridPoint(0, 12), rotation: 1),
            Component(kind: .netLabel, name: "in", position: GridPoint(0, 10)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 14)),
        ])
        let netlist = try Netlist(circuit: circuit)
        let u1 = try #require(netlist.elements.first { $0.name == "U1" })
        let inNode = try #require(netlist.nodeNames.firstIndex(of: "in"))
        let outNode = try #require(netlist.nodeNames.firstIndex(of: "out"))
        #expect(u1.nodes == [inNode, outNode, outNode])
        #expect(u1.outputNode == outNode)
        // The output net has only the op-amp on it, through two of its own pins.
        #expect(netlist.warnings.isEmpty, "\(netlist.warnings)")
    }

    @Test func warnsAboutUnconnectedOpAmpOutput() throws {
        let circuit = Circuit(components: [
            Component(kind: .opAmp, name: "U1", position: GridPoint(2, 1)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 2)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 0)),
        ])
        let netlist = try Netlist(circuit: circuit)
        #expect(netlist.warnings == ["The output of U1 is not connected to anything."])
    }

    @Test func opAmpWithAllPinsOnOneNetIsIgnored() throws {
        let circuit = Circuit(
            components: [
                Component(kind: .opAmp, name: "U1", position: GridPoint(2, 1)),
                Component(kind: .resistor, name: "R1", position: GridPoint(2, 6)),
                Component(kind: .ground, name: "GND", position: GridPoint(0, 6)),
            ],
            wires: [
                Wire(start: GridPoint(0, 2), end: GridPoint(0, 0)),
                Wire(start: GridPoint(0, 0), end: GridPoint(4, 0)),
                Wire(start: GridPoint(4, 0), end: GridPoint(4, 1)),
                Wire(start: GridPoint(0, 2), end: GridPoint(0, 6)),
            ])
        let netlist = try Netlist(circuit: circuit)
        #expect(netlist.elements.map(\.name) == ["R1"])
        #expect(netlist.warnings.contains("U1 is shorted (all pins on net 0) and was ignored."))
    }

    @Test func diodeValuesAreChecked() {
        func circuit(_ diode: Component) -> Circuit {
            Circuit(components: [diode, Component(kind: .ground, name: "GND", position: .zero)])
        }
        let zeroCurrent = Component(kind: .diode, name: "D1", position: GridPoint(2, 0), value: 0)
        #expect(throws: NetlistError.invalidValue(component: "D1", reason: "saturation current must be greater than zero.")) {
            try Netlist(circuit: circuit(zeroCurrent))
        }
        let zeroEmission = Component(kind: .diode, name: "D1", position: GridPoint(2, 0), emissionCoefficient: 0)
        #expect(throws: NetlistError.invalidValue(component: "D1", reason: "emission coefficient must be greater than zero.")) {
            try Netlist(circuit: circuit(zeroEmission))
        }
    }

    @Test func warnsAboutUnconnectedAnode() throws {
        let circuit = Circuit(components: [
            Component(kind: .diode, name: "D1", position: GridPoint(2, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(4, 0)),
        ])
        #expect(try Netlist(circuit: circuit).warnings == ["The anode of D1 is not connected to anything."])
    }

    @Test func emissionCoefficientIsOptionalInDocuments() throws {
        // Documents without diode parameters, such as those saved before diodes existed, still decode.
        let plain = Examples.voltageDivider.circuit
        let data = try plain.encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains("emissionCoefficient"))
        #expect(try Circuit.decoded(from: data) == plain)

        var diode = plain
        diode.components.append(Component(kind: .diode, name: "D1", position: GridPoint(40, 6), emissionCoefficient: 1.8))
        #expect(try Circuit.decoded(from: diode.encoded()) == diode)
    }

    @Test func pTypeTransistorsAreDrawnUpsideDown() {
        let npn = Component(kind: .bjt, name: "Q1", position: GridPoint(10, 10))
        #expect(npn.pinPositions == [GridPoint(11, 8), GridPoint(8, 10), GridPoint(11, 12)])
        // The emitter goes on top, the collector at the bottom.
        let pnp = Component(kind: .bjt, name: "Q2", position: GridPoint(10, 10), transistor: TransistorParameters(polarity: .p))
        #expect(pnp.pinPositions == [GridPoint(11, 12), GridPoint(8, 10), GridPoint(11, 8)])
        #expect(Component(kind: .mosfet, name: "M1", position: .zero).transistor == TransistorParameters())
        #expect(Component(kind: .resistor, name: "R1", position: .zero).transistor == nil)
    }

    @Test func transistorValuesAreChecked() {
        func netlist(_ part: Component) throws -> Netlist {
            try Netlist(circuit: Circuit(components: [part, Component(kind: .ground, name: "GND", position: GridPoint(-2, 0))]))
        }
        #expect(throws: NetlistError.invalidValue(component: "Q1", reason: "current gain β must be greater than zero.")) {
            try netlist(Component(kind: .bjt, name: "Q1", position: .zero, value: 0))
        }
        var parameters = TransistorParameters()
        parameters.transconductance = 0
        #expect(throws: NetlistError.invalidValue(component: "M1", reason: "transconductance parameter k must be greater than zero.")) {
            try netlist(Component(kind: .mosfet, name: "M1", position: .zero, transistor: parameters))
        }
    }

    @Test func warnsAboutUnconnectedTransistorPins() throws {
        // Only the gate is grounded: the drain and source are left open.
        let circuit = Circuit(components: [
            Component(kind: .mosfet, name: "M1", position: GridPoint(2, 0)),
            Component(kind: .ground, name: "GND", position: GridPoint(0, 0)),
        ])
        #expect(try Netlist(circuit: circuit).warnings == [
            "The drain of M1 is not connected to anything.", "The source of M1 is not connected to anything.",
        ])
    }

    @Test func transistorParametersDecodeWithMissingKeys() throws {
        let decoded = try JSONDecoder().decode(TransistorParameters.self, from: Data(#"{"polarity": "p"}"#.utf8))
        var expected = TransistorParameters(polarity: .p)
        #expect(decoded == expected)
        expected.earlyVoltage = 80
        #expect(try JSONDecoder().decode(TransistorParameters.self, from: JSONEncoder().encode(expected)) == expected)
    }

    @Test func documentRoundTrip() throws {
        let circuit = Examples.all.first!.circuit
        let decoded = try Circuit.decoded(from: circuit.encoded())
        #expect(decoded == circuit)
    }

    @Test(arguments: Examples.all.map(\.name))
    func examplesSimulate(name: String) throws {
        let example = Examples.all.first { $0.name == name }!
        let netlist = try Netlist(circuit: example.circuit)
        #expect(netlist.warnings.isEmpty, "\(netlist.warnings)")
        _ = try Simulator.run(example.circuit)
    }
}
