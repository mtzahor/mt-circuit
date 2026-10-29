import Foundation

// MARK: - Functions

/// The Boolean function a logic gate computes.
public enum LogicFunction: String, Codable, CaseIterable, Sendable {
    case and, or, not, nand, nor, xor, xnor

    public var displayName: String { rawValue.uppercased() }

    /// One input for NOT, two for the others.
    public var inputCount: Int { self == .not ? 1 : 2 }

    /// Whether the symbol has a bubble on its output: NOT, NAND, NOR, and XNOR.
    public var isInverting: Bool { [.not, .nand, .nor, .xnor].contains(self) }

    public func evaluate(_ inputs: [Bool]) -> Bool {
        smooth(inputs.map { $0 ? 1 : 0 }).value == 1
    }

    /// The function on input levels between 0 and 1, with its slope with respect to each level:
    /// AND is the product of the levels, NOT is 1 minus the level, and the others follow. It is
    /// exact at 0 and 1 and smooth in between, so Newton–Raphson iteration can solve circuits of gates.
    func smooth(_ x: [Double]) -> (value: Double, slopes: [Double]) {
        let a = x[0], b = x.count > 1 ? x[1] : 0
        let (value, da, db): (Double, Double, Double) = switch self {
        case .not: (1 - a, -1, 0)
        case .and: (a * b, b, a)
        case .nand: (1 - a * b, -b, -a)
        case .or: (a + b - a * b, 1 - b, 1 - a)
        case .nor: ((1 - a) * (1 - b), b - 1, a - 1)
        case .xor: (a + b - 2 * a * b, 1 - 2 * b, 1 - 2 * a)
        case .xnor: (1 - a - b + 2 * a * b, 2 * b - 1, 2 * a - 1)
        }
        return (value, Array([da, db].prefix(inputCount)))
    }
}

// MARK: - Parameters

/// A logic gate's function and timing. Its supply voltage is the component's value.
public struct LogicParameters: Codable, Hashable, Sendable {
    public static let defaultDelay = 10e-9

    public var function: LogicFunction = .and
    /// Propagation delay t_pd: how long the output lags behind its inputs.
    public var delay = LogicParameters.defaultDelay

    public init(function: LogicFunction = .and) {
        self.function = function
    }

    /// Missing keys take their defaults, so that parameters added later keep older documents readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LogicParameters()
        function = try container.decodeIfPresent(LogicFunction.self, forKey: .function) ?? defaults.function
        delay = try container.decodeIfPresent(Double.self, forKey: .delay) ?? defaults.delay
    }
}

// MARK: - Model

/// A CMOS logic gate as the simulator sees it. Its supply is implicit: the output drives toward
/// 0 V or the supply voltage V_DD, relative to ground, through an output resistance R_out. Inputs
/// switch at V_DD/2 and draw no current.
///
/// Each input's voltage v becomes a level x = 1 / (1 + exp(−(v − V_DD/2)/w)) between 0 and 1,
/// with w = V_DD/100, and the output drives toward V_DD·f(x) (see `LogicFunction.smooth`). Near
/// the threshold the gate amplifies, with a gain of 25 for an inverter, as a real CMOS gate does.
///
/// The output follows that target one propagation delay later, s(t) = V_DD·f(x(t − t_pd)): a
/// pure delay, as in digital simulators, so a ring of N inverters oscillates with a period of
/// 2·N·t_pd. The output current, into the output pin, is I = (V(out) − s) / R_out.
public struct LogicGateModel: Hashable, Sendable {
    public static let outputResistance = 50.0
    /// Width w of the input transition, as a fraction of the supply.
    static let transitionWidth = 0.01
    /// Output voltages at or above this fraction of the supply read as 1, and at or below
    /// 1 minus it as 0, like the input levels of 74HC logic.
    public static let highFraction = 0.7

    public var function: LogicFunction
    /// V_DD: the voltage of a 1.
    public var supply: Double
    /// Propagation delay t_pd.
    public var delay: Double

    public init(function: LogicFunction, supply: Double = 5, delay: Double = LogicParameters.defaultDelay) {
        self.function = function
        self.supply = supply
        self.delay = delay
    }

    public var threshold: Double { supply / 2 }

    /// The level of an input at voltage `v`, between 0 and 1, and its slope dx/dv.
    func level(_ v: Double) -> (x: Double, slope: Double) {
        let w = Self.transitionWidth * supply
        let z = (v - threshold) / w
        // Written so that exp never overflows.
        let e = exp(-abs(z))
        let x = z >= 0 ? 1 / (1 + e) : e / (1 + e)
        return (x, x * (1 - x) / w)
    }

    /// The voltage the output drives toward at input voltages `inputs`, and its slope with respect to each.
    public func target(_ inputs: [Double]) -> (voltage: Double, slopes: [Double]) {
        let levels = inputs.map(level)
        let (value, slopes) = function.smooth(levels.map(\.x))
        return (supply * value, zip(slopes, levels).map { supply * $0 * $1.slope })
    }

    /// The logic value a voltage stands for: 1 near the supply, 0 near ground, and nil in between.
    public func logicValue(_ v: Double) -> Bool? {
        if v >= Self.highFraction * supply { return true }
        if v <= (1 - Self.highFraction) * supply { return false }
        return nil
    }

    /// The output during one solution: it drives toward s = `hold` + `drive`·target.
    func step(hold: Double, drive: Double) -> LogicGateStep {
        LogicGateStep(gate: self, hold: hold, drive: drive)
    }
}

/// A gate's output current for one DC solution or time step, as Newton–Raphson iteration sees it.
/// Its control voltages are the output's, then each input's, all relative to ground.
struct LogicGateStep: NonlinearModel {
    var gate: LogicGateModel
    /// The part of s known before solving: the target one propagation delay ago.
    var hold: Double
    /// How much s depends on the target at the present, unknown input voltages: 1 at DC, 0 when the
    /// delay reaches back past the previous time point or the output is held at rest.
    var drive: Double

    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let r = LogicGateModel.outputResistance
        let (target, slopes) = gate.target(Array(v.dropFirst()))
        let state = hold + drive * target
        return ([(v[0] - state) / r], [[1 / r] + slopes.map { -drive * $0 / r }])
    }

    /// An input that jumps across the threshold lands just past it instead, where the gate's
    /// gain shows, much as SPICE limits the steps of a pn junction. Otherwise the tangent at a
    /// settled input is flat, and gates that feed each other back can flip back and forth forever.
    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        let w = LogicGateModel.transitionWidth * gate.supply
        return new.indices.map { j in
            guard j > 0 else { return new[j] }
            let before = (old[j] - gate.threshold) / w, after = (new[j] - gate.threshold) / w
            guard (before < 0) != (after < 0), abs(after - before) > 2 else { return new[j] }
            return gate.threshold + (after > 0 ? w : -w)
        }
    }
}

// MARK: - Delay

/// A logic gate's target voltage at each time point of a transient analysis, so that its output
/// can follow the target one propagation delay later.
struct GateHistory {
    /// The target before the first time point: 0 V for a gate that starts from rest.
    var initial: Double
    private var times: [Double] = []
    private var targets: [Double] = []
    /// Index of the oldest time point still needed.
    private var start = 0

    init(initial: Double) {
        self.initial = initial
    }

    /// The target at time `t`, interpolated linearly between time points.
    func target(at t: Double) -> Double {
        guard start < times.count, t >= times[start] else { return start == 0 ? initial : targets[start] }
        var low = start, high = times.count - 1
        if t >= times[high] { return targets[high] }
        while high - low > 1 {
            let middle = (low + high) / 2
            if times[middle] <= t { low = middle } else { high = middle }
        }
        let fraction = (t - times[low]) / (times[high] - times[low])
        return targets[low] + fraction * (targets[high] - targets[low])
    }

    /// Records the target at time `t`, which is later than every time recorded so far, and forgets
    /// the points that lookups of `t − delay` or later no longer need.
    mutating func record(_ target: Double, at t: Double, delay: Double) {
        times.append(t)
        targets.append(target)
        while start + 1 < times.count, times[start + 1] <= t - delay { start += 1 }
        if start > 4096, 2 * start > times.count {
            times.removeFirst(start)
            targets.removeFirst(start)
            start = 0
        }
    }
}
