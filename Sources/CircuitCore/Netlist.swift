import Foundation

/// A circuit element after connectivity has been resolved.
public struct NetlistElement: Sendable, Hashable {
    public var componentID: UUID
    public var name: String
    public var kind: ComponentKind
    /// Node index of each pin, in pin order; node 0 is ground.
    public var nodes: [Int]
    public var value: Double
    public var waveform: SourceWaveform
    /// A diode's emission coefficient n (1 for other elements).
    public var emissionCoefficient: Double
    /// A transistor's polarity and parameters (the defaults for other elements).
    public var transistor: TransistorParameters
    /// A logic gate's function and delay (the defaults for other elements).
    public var logic: LogicParameters
    /// A comparator's or voltage regulator's parameters (the defaults for other elements).
    public var chip: ChipParameters

    /// A diode's model; its saturation current is `value`.
    public var diode: DiodeModel {
        DiodeModel(saturationCurrent: value, emissionCoefficient: emissionCoefficient)
    }

    /// A BJT's model; its current gain β is `value`.
    public var bjt: BJTModel {
        BJTModel(
            polarity: transistor.polarity, beta: value,
            saturationCurrent: transistor.saturationCurrent, earlyVoltage: transistor.earlyVoltage)
    }

    /// A MOSFET's model; its threshold voltage is `value`.
    public var mosfet: MOSFETModel {
        MOSFETModel(
            polarity: transistor.polarity, threshold: value,
            transconductance: transistor.transconductance, channelLengthModulation: transistor.channelLengthModulation)
    }

    /// A logic gate's model; its supply voltage is `value`.
    public var gate: LogicGateModel {
        LogicGateModel(function: logic.function, supply: value, delay: logic.delay)
    }

    /// A comparator's model; its supply voltage is `value`.
    public var comparator: ComparatorModel {
        ComparatorModel(supply: value, delay: chip.delay)
    }

    /// A voltage regulator's model; its reference voltage is `value`.
    public var regulator: RegulatorModel {
        RegulatorModel(reference: value, dropout: chip.dropout, adjustCurrent: chip.adjustCurrent)
    }

    /// The model of a diode, transistor, comparator, logic gate, 555 timer, or voltage regulator,
    /// whose currents are nonlinear in its voltages. A comparator's, logic gate's, or 555's is its
    /// DC model; in a transient analysis, its output also depends on its previous state (see
    /// `Simulator.nonlinearModels`).
    var nonlinearModel: (any NonlinearModel)? {
        switch kind {
        case .diode: diode
        case .bjt: bjt
        case .mosfet: mosfet
        case .comparator: comparator.step(hold: 0, drive: 1)
        case .logicGate: gate.step(hold: 0, drive: 1)
        case .timer: TimerModel.step(state: nil)
        case .regulator: regulator
        default: nil
        }
    }

    /// Whether the element's output follows its inputs one propagation delay later, so that a
    /// transient analysis keeps its history: a comparator, logic gate, or 555 timer.
    var isDelayed: Bool { kind == .comparator || kind == .logicGate || kind == .timer }

    /// A comparator's, logic gate's, or 555's propagation delay.
    var delay: Double {
        switch kind {
        case .comparator: chip.delay
        case .timer: TimerModel.delay
        default: logic.delay
        }
    }

    /// Where each of the element's currents flows inside it, from one node to another. The first
    /// is its main current: through a two-terminal element, out of an op-amp's, comparator's, or
    /// logic gate's output to ground, collector to emitter (Ic) of a BJT, drain to source (Id) of a
    /// MOSFET, into a 555's output and on to its GND pin, or from a regulator's input to its output.
    /// A BJT's second current is its base current, base to emitter; a 555's are the current from
    /// VCC into its output's pull-up, and into its discharge pin, each on to GND.
    public var branchNodes: [(from: Int, to: Int)] {
        switch kind {
        case .opAmp, .comparator, .logicGate: [(outputNode, 0)]
        case .bjt: [(nodes[0], nodes[2]), (nodes[1], nodes[2])]
        case .mosfet: [(nodes[0], nodes[2])]
        // Pins: GND 0, OUT 2, DIS 6, VCC 7.
        case .timer: [(nodes[2], nodes[0]), (nodes[7], nodes[0]), (nodes[6], nodes[0])]
        default: [(nodeA, nodeB)]
        }
    }

    /// Names of the currents in `branchNodes`: "I(R1)", or "Ic(Q1)" and "Ib(Q1)", "Id(M1)", or
    /// "I(U1)", "Iup(U1)", and "Idis(U1)".
    public var currentNames: [String] {
        switch kind {
        case .bjt: ["Ic(\(name))", "Ib(\(name))"]
        case .mosfet: ["Id(\(name))"]
        case .timer: ["I(\(name))", "Iup(\(name))", "Idis(\(name))"]
        default: ["I(\(name))"]
        }
    }

    /// Resistors inside the element, which the simulator stamps like resistors: a 555's divider,
    /// 5 kΩ from VCC to CTRL and 10 kΩ from CTRL to GND.
    var internalResistors: [(from: Int, to: Int, resistance: Double)] {
        guard kind == .timer else { return [] }
        // Pins: GND 0, CTRL 4, VCC 7.
        return [(nodes[7], nodes[4], TimerModel.upperDivider), (nodes[4], nodes[0], TimerModel.lowerDivider)]
    }

    /// Constant currents inside the element, which the simulator stamps like current sources: a
    /// voltage regulator's ADJ current, from its input out of its ADJ pin.
    var internalCurrents: [(from: Int, to: Int, current: Double)] {
        guard kind == .regulator, chip.adjustCurrent != 0 else { return [] }
        return [(nodes[0], nodes[2], chip.adjustCurrent)]
    }

    /// Number of branch currents the simulator solves for: one per voltage source, inductor,
    /// capacitor, diode, op-amp, MOSFET, comparator, logic gate, and voltage regulator, two per BJT,
    /// three per 555 timer, and none for resistors and current sources.
    var branchCount: Int {
        switch kind {
        case .resistor, .currentSource, .ground, .netLabel: 0
        default: branchNodes.count
        }
    }

    /// Node pairs whose voltage differences control a nonlinear element's currents: a diode's
    /// V(anode) − V(cathode), a BJT's V_BE and V_BC, a MOSFET's V_GS and V_DS, a logic gate's
    /// output voltage and then input voltages, relative to ground, a comparator's output voltage
    /// and V+ − V−, a 555's OUT, VCC, DIS, TRIG, CTRL, and RESET relative to its GND pin, and a
    /// regulator's V(ADJ) − V(OUT) and V(IN) − V(OUT).
    var controlNodes: [(Int, Int)] {
        switch kind {
        case .bjt: [(nodes[1], nodes[2]), (nodes[1], nodes[0])]
        case .mosfet: [(nodes[1], nodes[2]), (nodes[0], nodes[2])]
        case .logicGate: ([outputNode] + inputNodes).map { ($0, 0) }
        case .comparator: [(outputNode, 0), (nodes[0], nodes[1])]
        // Pins: GND 0, TRIG 1, OUT 2, RESET 3, CTRL 4, DIS 6, VCC 7.
        case .timer: [2, 7, 6, 1, 4, 3].map { (nodes[$0], nodes[0]) }
        case .regulator: [(nodes[2], nodes[1]), (nodes[0], nodes[1])]
        default: [(nodeA, nodeB)]
        }
    }

    /// Node of pin 1: the "+" / "from" terminal, a diode's anode, or an op-amp's or comparator's
    /// non-inverting input.
    public var nodeA: Int { nodes[0] }
    /// Node of pin 2: the "−" / "to" terminal, a diode's cathode, or an op-amp's or comparator's
    /// inverting input.
    public var nodeB: Int { nodes[1] }
    /// Node of an output: an op-amp's, comparator's, or logic gate's last pin, a 555's pin 3, or a regulator's pin 2.
    public var outputNode: Int {
        switch kind {
        case .timer: nodes[2]
        case .regulator: nodes[1]
        default: nodes[nodes.count - 1]
        }
    }
    /// Nodes of a logic gate's inputs: every pin but the output.
    public var inputNodes: [Int] { Array(nodes.dropLast()) }

    /// Whether every pin is on the same net, so the element cannot affect any node voltage.
    var isShorted: Bool { nodes.allSatisfy { $0 == nodes[0] } }
}

public enum NetlistError: Error, LocalizedError, Equatable {
    case empty
    case noGround
    case invalidValue(component: String, reason: String)
    case shortedSource(component: String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "The schematic has no circuit elements to simulate."
        case .noGround:
            "Add a ground symbol: the simulator needs a reference node (0 V)."
        case let .invalidValue(component, reason):
            "\(component): \(reason)"
        case let .shortedSource(component):
            "\(component) is short-circuited (both terminals are on the same net)."
        }
    }
}

/// The electrical view of a schematic: nets numbered 0…n (0 is ground) and the elements between them.
public struct Netlist: Sendable {
    /// Display name of each node; index 0 is ground.
    public private(set) var nodeNames: [String]
    public private(set) var elements: [NetlistElement]
    /// Node index for every grid point that is part of a net (pins, wire endpoints).
    public private(set) var nodeAtPoint: [GridPoint: Int]
    /// Node index for every wire that is connected to at least one pin.
    public private(set) var nodeForWire: [UUID: Int]
    /// Non-fatal problems detected while building the netlist.
    public private(set) var warnings: [String]

    public var nodeCount: Int { nodeNames.count }

    public init(circuit: Circuit) throws {
        let elementKinds: Set<ComponentKind> = [
            .resistor, .capacitor, .inductor, .diode, .bjt, .mosfet, .voltageSource, .currentSource, .opAmp,
            .comparator, .logicGate, .timer, .regulator,
        ]
        let parts = circuit.components.filter { elementKinds.contains($0.kind) }
        guard !parts.isEmpty else { throw NetlistError.empty }

        for part in parts {
            switch part.kind {
            case .resistor, .capacitor, .inductor:
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(
                        component: part.name, reason: "\(part.kind.displayName.lowercased()) value must be greater than zero.")
                }
            case .diode:
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "saturation current must be greater than zero.")
                }
                if let n = part.emissionCoefficient, !(n.isFinite && n > 0) {
                    throw NetlistError.invalidValue(component: part.name, reason: "emission coefficient must be greater than zero.")
                }
            case .bjt:
                let parameters = part.transistor ?? TransistorParameters()
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "current gain β must be greater than zero.")
                }
                guard parameters.saturationCurrent.isFinite, parameters.saturationCurrent > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "saturation current must be greater than zero.")
                }
                guard parameters.earlyVoltage.isFinite, parameters.earlyVoltage >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "Early voltage must be positive, or 0 for none.")
                }
            case .mosfet:
                let parameters = part.transistor ?? TransistorParameters()
                guard part.value.isFinite else {
                    throw NetlistError.invalidValue(component: part.name, reason: "threshold voltage is not a number.")
                }
                guard parameters.transconductance.isFinite, parameters.transconductance > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "transconductance parameter k must be greater than zero.")
                }
                guard parameters.channelLengthModulation.isFinite, parameters.channelLengthModulation >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "λ must be positive, or 0 for none.")
                }
            case .opAmp:
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "open-loop gain must be greater than zero.")
                }
            case .logicGate:
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "supply voltage must be greater than zero.")
                }
                let delay = (part.logic ?? LogicParameters()).delay
                guard delay.isFinite, delay >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "propagation delay must be positive, or 0 for none.")
                }
            case .comparator:
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "supply voltage must be greater than zero.")
                }
                let delay = (part.chip ?? ChipParameters()).delay
                guard delay.isFinite, delay >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "propagation delay must be positive, or 0 for none.")
                }
            case .timer:
                break
            case .regulator:
                let parameters = part.chip ?? ChipParameters()
                guard part.value.isFinite, part.value > 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "reference voltage must be greater than zero.")
                }
                guard parameters.dropout.isFinite, parameters.dropout >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "dropout voltage must be positive, or 0 for none.")
                }
                guard parameters.adjustCurrent.isFinite, parameters.adjustCurrent >= 0 else {
                    throw NetlistError.invalidValue(component: part.name, reason: "ADJ current must be positive, or 0 for none.")
                }
            default:
                guard part.value.isFinite else {
                    throw NetlistError.invalidValue(component: part.name, reason: "source value is not a number.")
                }
            }
        }

        let connectivity = Connectivity(circuit: circuit)
        guard let groundNet = connectivity.groundNet else { throw NetlistError.noGround }

        // Number the nodes: ground is 0, the rest in order of first appearance on element pins.
        var nodeForNet: [Int: Int] = [groundNet: 0]
        var names = ["0"]
        var labeledNodes: Set<Int> = []
        var unnamedCount = 0
        func node(for point: GridPoint) -> Int {
            let net = connectivity.netAtPoint[point]!
            if let existing = nodeForNet[net] { return existing }
            let index = names.count
            nodeForNet[net] = index
            if let label = connectivity.labelForNet[net] {
                names.append(label)
                labeledNodes.insert(index)
            } else {
                unnamedCount += 1
                names.append("N\(unnamedCount)")
            }
            return index
        }

        var elements: [NetlistElement] = []
        var terminalsOnNode: [Int: Int] = [:]
        for part in parts {
            let nodes = part.pinPositions.map(node(for:))
            for node in nodes { terminalsOnNode[node, default: 0] += 1 }
            elements.append(NetlistElement(
                componentID: part.id, name: part.name, kind: part.kind,
                nodes: nodes, value: part.value, waveform: part.waveform,
                emissionCoefficient: part.emissionCoefficient ?? 1,
                transistor: part.transistor ?? TransistorParameters(),
                logic: part.logic ?? LogicParameters(),
                chip: part.chip ?? ChipParameters()))
        }

        var warnings: [String] = []
        for element in elements where element.isShorted {
            if element.kind == .voltageSource {
                throw NetlistError.shortedSource(component: element.name)
            }
            let pins = element.nodes.count == 2 ? "both terminals" : "all pins"
            warnings.append("\(element.name) is shorted (\(pins) on net \(names[element.nodeA])) and was ignored.")
        }
        // A shorted element cannot affect any node voltage, and would make the DC equations singular.
        elements.removeAll { $0.isShorted }
        for element in elements {
            for (pinIndex, node) in element.nodes.enumerated() where node != 0 && terminalsOnNode[node] == 1 {
                // An output may drive just a labeled net, to be observed.
                if element.kind.hasOutput, node == element.outputNode, labeledNodes.contains(node) { continue }
                // A 555's divider holds its CTRL pin at ⅔ of the supply, so it may be left open.
                if element.kind == .timer, pinIndex == 4 { continue }
                warnings.append("\(element.kind.pinName(pinIndex, of: element.nodes.count)) of \(element.name) is not connected to anything.")
            }
        }

        var nodeAtPoint: [GridPoint: Int] = [:]
        for (point, net) in connectivity.netAtPoint {
            if let index = nodeForNet[net] { nodeAtPoint[point] = index }
        }
        var nodeForWire: [UUID: Int] = [:]
        for (wire, net) in connectivity.netForWire {
            if let index = nodeForNet[net] { nodeForWire[wire] = index }
        }

        self.nodeNames = names
        self.elements = elements
        self.nodeAtPoint = nodeAtPoint
        self.nodeForWire = nodeForWire
        self.warnings = warnings
    }

    /// The node a net label or ground symbol sits on, if any.
    public func node(forComponent component: Component) -> Int? {
        component.pinPositions.first.flatMap { nodeAtPoint[$0] }
    }
}

// MARK: - Connectivity

/// Which pins and wires are electrically connected. Unlike `Netlist`, this never fails,
/// so the editor can use it for incomplete schematics.
public struct Connectivity: Sendable {
    /// Net number (0..<netCount, arbitrary order) of every pin and wire endpoint.
    public private(set) var netAtPoint: [GridPoint: Int] = [:]
    public private(set) var netForWire: [UUID: Int] = [:]
    public private(set) var netCount = 0
    /// Number of pins, wire ends, and wire pass-throughs meeting at each pin / wire endpoint.
    public private(set) var connectionCount: [GridPoint: Int] = [:]
    /// The net all ground symbols are on, if there is any ground symbol.
    public private(set) var groundNet: Int?
    /// Net-label name of each labelled net (alphabetically first label if there are several).
    public private(set) var labelForNet: [Int: String] = [:]

    public init(circuit: Circuit) {
        var uf = UnionFind<GridPoint>()
        var count: [GridPoint: Int] = [:]
        for component in circuit.components {
            for pin in component.pinPositions {
                uf.add(pin)
                count[pin, default: 0] += 1
            }
        }
        for wire in circuit.wires {
            uf.union(wire.start, wire.end)
            count[wire.start, default: 0] += 1
            count[wire.end, default: 0] += 1
        }
        // T-junctions: any pin or wire endpoint lying inside a wire joins that wire's net.
        let points = Array(count.keys)
        for wire in circuit.wires where wire.start != wire.end {
            for point in points where point != wire.start && point != wire.end
                && point.lies(onSegmentFrom: wire.start, to: wire.end) {
                uf.union(point, wire.start)
                count[point, default: 0] += 2
            }
        }
        // Net labels with the same name are connected; ground symbols are all one net.
        var labelAnchor: [String: GridPoint] = [:]
        var groundAnchor: GridPoint?
        for component in circuit.components {
            guard let pin = component.pinPositions.first else { continue }
            switch component.kind {
            case .ground:
                if let anchor = groundAnchor { uf.union(anchor, pin) } else { groundAnchor = pin }
            case .netLabel:
                let key = component.name.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                if let anchor = labelAnchor[key] { uf.union(anchor, pin) } else { labelAnchor[key] = pin }
            default:
                break
            }
        }

        var netForRoot: [GridPoint: Int] = [:]
        // Deterministic numbering: sort points so the same schematic always yields the same nets.
        for point in points.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            let root = uf.find(point)
            if netForRoot[root] == nil {
                netForRoot[root] = netCount
                netCount += 1
            }
            netAtPoint[point] = netForRoot[root]
        }
        for wire in circuit.wires {
            netForWire[wire.id] = netAtPoint[wire.start]
        }
        connectionCount = count
        groundNet = groundAnchor.flatMap { netAtPoint[$0] }
        for (name, anchor) in labelAnchor.sorted(by: { $0.key < $1.key }) {
            if let net = netAtPoint[anchor], labelForNet[net] == nil { labelForNet[net] = name }
        }
    }
}

// MARK: - Union-find

struct UnionFind<Element: Hashable> {
    private var parent: [Element: Element] = [:]
    private var rank: [Element: Int] = [:]

    mutating func add(_ element: Element) {
        if parent[element] == nil {
            parent[element] = element
            rank[element] = 0
        }
    }

    mutating func find(_ element: Element) -> Element {
        add(element)
        var root = element
        while let p = parent[root], p != root { root = p }
        // Path compression.
        var current = element
        while let p = parent[current], p != root {
            parent[current] = root
            current = p
        }
        return root
    }

    mutating func union(_ a: Element, _ b: Element) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        let rankA = rank[ra] ?? 0, rankB = rank[rb] ?? 0
        if rankA < rankB {
            parent[ra] = rb
        } else if rankA > rankB {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] = rankA + 1
        }
    }
}
