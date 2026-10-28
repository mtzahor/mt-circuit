import Foundation
import Testing
@testable import CircuitCore

private func operatingPoint(_ circuit: Circuit) throws -> (SimulationResult, OperatingPoint) {
    var circuit = circuit
    circuit.simulation.analysis = .operatingPoint
    let result = try Simulator.run(circuit)
    guard case let .operatingPoint(op) = result.output else { throw SimulationError.cancelled }
    return (result, op)
}

private func current(_ name: String, _ result: SimulationResult, _ op: OperatingPoint) -> Double {
    op.elementCurrents[result.netlist.elements.firstIndex { $0.name == name }!]
}

private func voltage(_ net: String, _ result: SimulationResult, _ op: OperatingPoint) -> Double {
    op.nodeVoltages[result.netlist.nodeNames.firstIndex(of: net)!]
}

private func setting(_ circuit: Circuit, _ name: String, _ change: (inout Component) -> Void) -> Circuit {
    var circuit = circuit
    change(&circuit.components[circuit.components.firstIndex { $0.name == name }!])
    return circuit
}

/// The topic IDs that the `divein:` links in `topic`'s text lead to.
private func links(in topic: DiveInTopic) -> [String] {
    topic.sections.flatMap { section in
        section.text.matches(of: /\]\(divein:([a-z\-]+)\)/).map { String($0.output.1) }
    }
}

@Suite struct DiveInTests {
    @Test func topicIDsAreUnique() {
        let ids = DiveIn.topics.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyPartHasATopic() {
        for kind in ComponentKind.allCases {
            let topic = DiveIn.topic(for: kind)
            #expect((topic != nil) == kind.hasValue, "\(kind)")
            #expect(topic.map { $0.category == .parts } ?? true)
        }
    }

    @Test(arguments: DiveIn.topics.map(\.id))
    func linksLeadToTopics(id: String) throws {
        let topic = try #require(DiveIn.topic(withID: id))
        for target in topic.deeper + links(in: topic) {
            #expect(DiveIn.topic(withID: target) != nil, "\(target)")
            #expect(target != id)
        }
        if let lesson = topic.lesson {
            #expect(Tutorial.lesson(withID: lesson) != nil, "\(lesson)")
        }
        #expect(DiveIn.topic(for: URL(string: "divein:\(id)")!)?.id == id)
    }

    @Test func containersListWhatUsesATopic() {
        let bjt = DiveIn.containers(of: "bjt").map(\.id)
        #expect(bjt.contains("op-amp"))
        #expect(bjt.contains("current-mirror"))
        #expect(DiveIn.containers(of: "op-amp").isEmpty)
    }

    @Test(arguments: DiveIn.topics.map(\.id))
    func regionsNameTheirParts(id: String) throws {
        let topic = try #require(DiveIn.topic(withID: id))
        guard case let .schematic(circuit, regions) = topic.figure else { return }
        let names = Set(circuit.components.map(\.name))
        for region in regions {
            #expect(!region.parts.isEmpty)
            #expect(Set(region.parts).isSubset(of: names), "\(region.title)")
        }
        for section in topic.sections {
            if let region = section.region { #expect(regions.indices.contains(region)) }
        }
    }

    @Test(arguments: DiveIn.topics.filter { $0.circuit != nil }.map(\.id))
    func circuitSimulatesCleanly(id: String) throws {
        let circuit = try #require(DiveIn.topic(withID: id)?.circuit)
        let result = try Simulator.run(circuit)
        #expect(result.netlist.warnings.isEmpty, "\(result.netlist.warnings)")
    }

    // MARK: Claims made in the text

    @Test func transistorOpAmpAmplifiesLikeTheIdealOne() throws {
        let amplifier = DiveInCircuits.opAmpAmplifier
        let (result, op) = try operatingPoint(amplifier)
        #expect(abs(voltage("out", result, op)) < 5e-3)
        // Every transistor is biased in its forward-active region.
        for element in result.netlist.elements where element.kind == .bjt {
            let v = { (pin: Int) in op.nodeVoltages[element.nodes[pin]] }
            #expect(element.bjt.region(vbe: v(1) - v(2), vbc: v(1) - v(0)) == .active, "\(element.name)")
        }
        // The diodes hold the output transistors' bases about 1.2 V apart.
        let bias = op.elementVoltages[result.netlist.elements.firstIndex { $0.name == "D1" }!] * 2
        #expect(abs(bias - 1.2) < 0.1)

        // Labeling the − input measures the open-loop gain: V(out) / V(in−).
        var probed = amplifier
        probed.components.append(Component(kind: .netLabel, name: "minus", position: GridPoint(14, 14)))
        probed.simulation.analysis = .ac
        probed.simulation.startFrequency = 1
        probed.simulation.stopFrequency = 1e7
        probed.simulation.pointsPerDecade = 20
        let sweep = try Simulator.run(probed)
        guard case let .ac(ac) = sweep.output else { throw SimulationError.cancelled }
        let node = { (name: String) in sweep.netlist.nodeNames.firstIndex(of: name)! }
        let openLoop = ac.frequencies.indices.map {
            ac.nodeVoltages[node("out")][$0].magnitude / ac.nodeVoltages[node("minus")][$0].magnitude
        }
        #expect(openLoop[0] > 150e3 && openLoop[0] < 250e3)
        let unity = ac.frequencies[openLoop.firstIndex { $0 < 1 }!]
        #expect(unity > 2e6 && unity < 4e6)
        let index = ac.frequencies.firstIndex { $0 >= 1e3 }!
        let gain = ac.nodeVoltages[node("out")][index] / ac.nodeVoltages[node("in")][index]
        #expect(abs(gain.re + 10) < 0.01)
    }

    @Test func differentialPairSteersItsTailCurrent() throws {
        let pair = DiveInCircuits.differentialPair
        let (result, op) = try operatingPoint(pair)
        #expect(abs(current("Q1", result, op) - current("Q2", result, op)) < 1e-9)
        let run = try Simulator.run(pair)
        guard case let .transient(transient) = run.output else { throw SimulationError.cancelled }
        let q1 = transient.elementCurrents[run.netlist.elements.firstIndex { $0.name == "Q1" }!]
        #expect(q1.max()! > 0.95e-3)
        #expect(q1.min()! < 0.05e-3)
    }

    @Test func currentMirrorCopiesTheReference() throws {
        let mirror = DiveInCircuits.currentMirror
        let (result, op) = try operatingPoint(mirror)
        let reference = current("Q1", result, op), copy = current("Q2", result, op)
        #expect(abs(copy / reference - 1) < 0.01)
        #expect(abs(copy - 1e-3) < 0.05e-3)
        // A transistor with twice the saturation current carries twice the current.
        let doubled = setting(mirror, "Q2") { $0.transistor?.saturationCurrent = 20e-15 }
        let (result2, op2) = try operatingPoint(doubled)
        #expect(abs(current("Q2", result2, op2) / current("Q1", result2, op2) - 2) < 0.02)
    }

    @Test func pushPullHasADeadZone() throws {
        let run = try Simulator.run(DiveInCircuits.pushPull)
        guard case let .transient(transient) = run.output else { throw SimulationError.cancelled }
        let node = { (name: String) in transient.nodeVoltages[run.netlist.nodeNames.firstIndex(of: name)!] }
        for (input, output) in zip(node("in"), node("out")) {
            if abs(input) < 0.45 { #expect(abs(output) < 0.01) }
            if abs(input) > 4.5 { #expect(abs(input - output) > 0.6 && abs(input - output) < 0.8) }
        }
    }

    @Test func batterySagsUnderLoad() throws {
        let (result, op) = try operatingPoint(DiveInCircuits.battery)
        #expect(abs(voltage("out", result, op) - 9 * 20 / 22) < 1e-6)
    }

    @Test(arguments: [1e3, 4.7e3, 9e3])
    func transistorCurrentSourceIgnoresTheLoad(load: Double) throws {
        let source = setting(DiveInCircuits.transistorCurrentSource, "RL") { $0.value = load }
        let (result, op) = try operatingPoint(source)
        #expect(abs(current("RL", result, op) - 1.04e-3) < 0.02e-3)
    }
}
