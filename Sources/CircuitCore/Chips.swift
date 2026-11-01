import Foundation

// MARK: - Smooth curves

/// The logistic curve 1/(1 + e^(−z)), between 0 and 1, and its slope, computed so that exp never overflows.
func logistic(_ z: Double) -> (value: Double, slope: Double) {
    let e = exp(-abs(z))
    let x = z >= 0 ? 1 / (1 + e) : e / (1 + e)
    return (x, x * (1 - x))
}

/// log(1 + e^z), a max(0, z) with its corner rounded, and its slope, the logistic curve.
func softPlus(_ z: Double) -> (value: Double, slope: Double) {
    (max(z, 0) + log1p(exp(-abs(z))), logistic(z).value)
}

/// min(a, b) with its corner rounded over `knee`, and its slopes with respect to a and b.
func softMin(_ a: Double, _ b: Double, knee: Double) -> (value: Double, slopeA: Double, slopeB: Double) {
    let z = (a - b) / knee
    let toB = logistic(z).value
    return (a - knee * softPlus(z).value, 1 - toB, toB)
}

// MARK: - Comparator

/// A comparator as the simulator sees it: a logic gate with one differential input. Its supply is
/// implicit: the output drives toward the supply voltage V_DD while V+ is above V−, and toward 0 V
/// while it is below, relative to ground, through an output resistance R_out, one propagation delay
/// later. The inputs draw no current.
///
/// In between, the output follows a logistic curve of V+ − V− over a width w of 1 mV, for a gain
/// of V_DD/(4w): 1250 at 5 V. A real comparator has far more, but this is enough to switch within a
/// few millivolts, and it keeps Newton–Raphson iteration smooth.
public struct ComparatorModel: Hashable, Sendable {
    public static let outputResistance = 50.0
    static let transitionWidth = 1e-3

    /// V_DD: the voltage of a high output.
    public var supply: Double
    /// Propagation delay t_pd.
    public var delay: Double

    public init(supply: Double = 5, delay: Double = ChipParameters.defaultComparatorDelay) {
        self.supply = supply
        self.delay = delay
    }

    /// The voltage the output drives toward at an input difference V+ − V− of `v`, and its slope.
    public func target(_ v: Double) -> (voltage: Double, slope: Double) {
        let (x, slope) = logistic(v / Self.transitionWidth)
        return (supply * x, supply * slope / Self.transitionWidth)
    }

    /// The output during one solution: it drives toward s = `hold` + `drive`·target, as a logic gate's does.
    func step(hold: Double, drive: Double) -> ComparatorStep {
        ComparatorStep(comparator: self, hold: hold, drive: drive)
    }
}

/// A comparator's output current for one DC solution or time step. Its control voltages are the
/// output's, relative to ground, and V+ − V−.
struct ComparatorStep: NonlinearModel {
    var comparator: ComparatorModel
    /// The part of s known before solving: the target one propagation delay ago.
    var hold: Double
    /// How much s depends on the target at the present, unknown inputs (see `LogicGateStep`).
    var drive: Double

    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let r = ComparatorModel.outputResistance
        let (target, slope) = comparator.target(v[1])
        return ([(v[0] - hold - drive * target) / r], [[1 / r, -drive * slope / r]])
    }

    /// An input difference that jumps across zero lands just past it instead, as a logic gate's input does.
    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        let w = ComparatorModel.transitionWidth
        let before = old[1] / w, after = new[1] / w
        guard (before < 0) != (after < 0), abs(after - before) > 2 else { return new }
        return [new[0], after > 0 ? w : -w]
    }
}

// MARK: - 555 timer

/// A 555 timer as the simulator sees it: the divider, comparators, and latch of the classic NE555,
/// with an output that swings from rail to rail, as a CMOS 555's does. All its voltages are
/// relative to its GND pin.
///
/// Three 5 kΩ resistors from VCC to GND hold CTRL at ⅔ of the supply. The trigger comparator sets
/// the latch while TRIG is below V(CTRL)/2, ⅓ of the supply; otherwise the threshold comparator
/// resets it while THR is above V(CTRL). RESET below 0.7 V resets it, whatever the comparators say.
///
/// While the latch is set (q = 1), the output connects to VCC through R_out. While it is reset
/// (q = 0), the output connects to GND through R_out, and so does the discharge pin, through R_dis.
/// I(U1) flows into the output, Iup(U1) from VCC into the output's pull-up, and Idis(U1) into the
/// discharge pin, each on to GND:
///
///     I = (V(OUT) − q·V(VCC))/R_out    Iup = q·(V(VCC) − V(OUT))/R_out    Idis = (1 − q)·V(DIS)/R_dis
///
/// In a transient analysis the latch updates after each time point, and the output and discharge
/// follow it one propagation delay later, or at the next time point if a step is longer. Within a
/// step q is known, so the timer is linear, and it can't settle halfway across a threshold, which
/// a real latch never does either. At DC, the latch starts reset: q = 1 only while the trigger and
/// reset inputs hold it set, and in between q follows logistic curves of them over 1 mV.
public enum TimerModel {
    public static let outputResistance = 10.0
    public static let dischargeResistance = 10.0
    /// The internal divider: one 5 kΩ resistor from VCC to CTRL, and two in series from CTRL to GND.
    public static let upperDivider = 5e3
    public static let lowerDivider = 10e3
    public static let resetThreshold = 0.7
    public static let delay = 100e-9
    static let transitionWidth = 1e-3

    /// The latch's next state at TRIG, THR, CTRL, and RESET voltages relative to GND: set while the
    /// trigger is below V(CTRL)/2, otherwise reset while the threshold is above V(CTRL), otherwise
    /// `previous`; and reset while RESET is below 0.7 V.
    public static func latch(trigger: Double, threshold: Double, control: Double, reset: Double, previous: Bool) -> Bool {
        guard reset > resetThreshold else { return false }
        if trigger < control / 2 { return true }
        if threshold > control { return false }
        return previous
    }

    /// The latch state at DC, and the currents into the output, the pull-up, and the discharge pin,
    /// at OUT, VCC, DIS, TRIG, CTRL, and RESET voltages `v`, relative to GND.
    public static func operatingPoint(_ v: [Double]) -> (latch: Double, output: Double, pullUp: Double, discharge: Double) {
        let step = TimerStep(state: nil)
        let currents = step.linearize(at: v).currents
        return (step.latch(v).q, currents[0], currents[1], currents[2])
    }

    /// The output and discharge during one solution, following the latch state `state`, from 0
    /// (reset) to 1 (set); at DC, `state` is nil.
    static func step(state: Double?) -> TimerStep {
        TimerStep(state: state)
    }
}

/// A 555's currents (see `TimerModel`) for one DC solution or time step. Its control voltages are
/// those of OUT, VCC, DIS, TRIG, CTRL, and RESET, relative to GND.
struct TimerStep: NonlinearModel {
    /// The latch state that the output and discharge follow; nil at DC.
    var state: Double?

    /// The latch state q at control voltages `v`, and its slopes with respect to them.
    func latch(_ v: [Double]) -> (q: Double, slopes: [Double]) {
        if let state { return (state, Array(repeating: 0, count: 6)) }
        let w = TimerModel.transitionWidth
        let (set, setSlope) = logistic((v[4] / 2 - v[3]) / w)
        let (enable, enableSlope) = logistic((v[5] - TimerModel.resetThreshold) / w)
        return (set * enable, [0, 0, 0, -enable * setSlope / w, enable * setSlope / (2 * w), set * enableSlope / w])
    }

    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let r = TimerModel.outputResistance, rd = TimerModel.dischargeResistance
        let (out, vcc, dis) = (v[0], v[1], v[2])
        let (q, dq) = latch(v)
        var jacobian = [
            dq.map { -vcc * $0 / r },
            dq.map { (vcc - out) * $0 / r },
            dq.map { -dis * $0 / rd },
        ]
        jacobian[0][0] += 1 / r
        jacobian[0][1] -= q / r
        jacobian[1][0] -= q / r
        jacobian[1][1] += q / r
        jacobian[2][2] += (1 - q) / rd
        return ([(out - q * vcc) / r, q * (vcc - out) / r, (1 - q) * dis / rd], jacobian)
    }

    /// At DC, a trigger or reset input that jumps across its threshold lands just past it instead,
    /// as a logic gate's input does.
    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        guard state == nil else { return new }
        let w = TimerModel.transitionWidth
        var limited = new
        func crosses(_ before: Double, _ after: Double) -> Bool {
            (before < 0) != (after < 0) && abs(after - before) > 2
        }
        let trigger = (before: (old[4] / 2 - old[3]) / w, after: (new[4] / 2 - new[3]) / w)
        if crosses(trigger.before, trigger.after) { limited[3] = new[4] / 2 - (trigger.after > 0 ? w : -w) }
        let reset = (before: (old[5] - TimerModel.resetThreshold) / w, after: (new[5] - TimerModel.resetThreshold) / w)
        if crosses(reset.before, reset.after) { limited[5] = TimerModel.resetThreshold + (reset.after > 0 ? w : -w) }
        return limited
    }
}

// MARK: - Voltage regulator

/// An adjustable linear regulator, like the LM317, as the simulator sees it. Its pass transistor
/// sources current from IN to OUT to hold OUT at the reference voltage V_ref above ADJ, as far as
/// the input allows: OUT can't rise above V(IN) − V_do, the dropout voltage. A fixed regulator,
/// like the 7805, is the same with ADJ grounded and V_ref = 5 V. The ADJ current I_adj flows from
/// IN out of the ADJ pin.
///
/// The output aims for V_set = min(V(ADJ) + V_ref, V(IN) − V_do), with the corner into dropout
/// rounded over 50 mV, through an output resistance R_out of 10 mΩ. The pass current I(U1), from IN
/// to OUT, is (V_set − V(OUT))/R_out; the pass transistor can't carry it backward, so where that
/// would be negative, it rounds off to zero over 0.1 mV.
public struct RegulatorModel: Hashable, Sendable {
    public static let outputResistance = 0.01
    static let dropoutKnee = 0.05
    static let cutoffKnee = 1e-4

    public var reference: Double
    public var dropout: Double
    public var adjustCurrent: Double

    public init(
        reference: Double = 1.25, dropout: Double = ChipParameters.defaultDropout,
        adjustCurrent: Double = ChipParameters.defaultAdjustCurrent
    ) {
        self.reference = reference
        self.dropout = dropout
        self.adjustCurrent = adjustCurrent
    }

    /// Whether the input is too low to regulate, with OUT at `output`, IN at `input`, and ADJ at `adjust`.
    public func isInDropout(input: Double, output: Double, adjust: Double) -> Bool {
        input - dropout < adjust + reference
    }
}

extension RegulatorModel: NonlinearModel {
    /// Control voltages: V(ADJ) − V(OUT), then V(IN) − V(OUT).
    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let r = Self.outputResistance, k = Self.cutoffKnee
        let set = softMin(v[0] + reference, v[1] - dropout, knee: Self.dropoutKnee)
        let (pass, conduction) = softPlus(set.value / k)
        return ([k * pass / r], [[conduction * set.slopeA / r, conduction * set.slopeB / r]])
    }

    func limitStep(_ new: [Double], from old: [Double]) -> [Double] { new }
}
