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

    /// The model of a diode or transistor, whose currents are nonlinear in its voltages.
    var nonlinearModel: (any NonlinearModel)? {
        switch kind {
        case .diode: diode
        case .bjt: bjt
        case .mosfet: mosfet
        default: nil
        }
    }

    /// Where each of the element's currents flows inside it, from one node to another. The first
    /// is its main current: through a two-terminal element, out of an op-amp's output to ground,
    /// collector to emitter (Ic) of a BJT, or drain to source (Id) of a MOSFET. A BJT's second
    /// current is its base current, base to emitter.
    public var branchNodes: [(from: Int, to: Int)] {
        switch kind {
        case .opAmp: [(nodes[2], 0)]
        case .bjt: [(nodes[0], nodes[2]), (nodes[1], nodes[2])]
        case .mosfet: [(nodes[0], nodes[2])]
        default: [(nodeA, nodeB)]
        }
    }

    /// Names of the currents in `branchNodes`: "I(R1)", or "Ic(Q1)" and "Ib(Q1)", or "Id(M1)".
    public var currentNames: [String] {
        switch kind {
        case .bjt: ["Ic(\(name))", "Ib(\(name))"]
        case .mosfet: ["Id(\(name))"]
        default: ["I(\(name))"]
        }
    }

    /// Number of branch currents the simulator solves for: one per voltage source, inductor,
    /// capacitor, diode, op-amp, and MOSFET, two per BJT, none for resistors and current sources.
    var branchCount: Int {
        switch kind {
        case .resistor, .currentSource, .ground, .netLabel: 0
        default: branchNodes.count
        }
    }

    /// Node pairs whose voltage differences control a nonlinear element's currents: a diode's
    /// V(anode) − V(cathode), a BJT's V_BE and V_BC, a MOSFET's V_GS and V_DS.
    var controlNodes: [(Int, Int)] {
        switch kind {
        case .bjt: [(nodes[1], nodes[2]), (nodes[1], nodes[0])]
        case .mosfet: [(nodes[1], nodes[2]), (nodes[0], nodes[2])]
        default: [(nodeA, nodeB)]
        }
    }

    /// Node of pin 1: the "+" / "from" terminal, a diode's anode, or an op-amp's non-inverting input.
    public var nodeA: Int { nodes[0] }
    /// Node of pin 2: the "−" / "to" terminal, a diode's cathode, or an op-amp's inverting input.
    public var nodeB: Int { nodes[1] }
    /// Node of an op-amp's output (pin 3). Only op-amps have one.
    public var outputNode: Int { nodes[2] }

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
        var unnamedCount = 0
        func node(for point: GridPoint) -> Int {
            let net = connectivity.netAtPoint[point]!
            if let existing = nodeForNet[net] { return existing }
            let index = names.count
            nodeForNet[net] = index
            if let label = connectivity.labelForNet[net] {
                names.append(label)
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
                transistor: part.transistor ?? TransistorParameters()))
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
                warnings.append("\(element.kind.pinName(pinIndex)) of \(element.name) is not connected to anything.")
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
