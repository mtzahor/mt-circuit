import Foundation

/// A nonlinear element as Newton–Raphson iteration sees it: currents that depend on a few
/// control voltages. Currents are in the order of `NetlistElement.branchNodes`, control voltages
/// in the order of `NetlistElement.controlNodes`.
protocol NonlinearModel: Sendable {
    /// The currents at control voltages `v`, and their slopes `jacobian[i][j] = ∂I_i/∂V_j`.
    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]])
    /// Limits a Newton step from control voltages `old` to `new` where the model would overshoot.
    func limitStep(_ new: [Double], from old: [Double]) -> [Double]
}

extension TransistorParameters.Polarity {
    /// +1 for N-type, −1 for P-type, whose laws are the N-type ones with voltages and currents negated.
    var sign: Double { self == .n ? 1 : -1 }
}

// MARK: - Diode

/// The Shockley diode equation, I = Is·(exp(V/(n·Vt)) − 1), with the voltage limiting that keeps
/// Newton–Raphson iteration on it stable.
public struct DiodeModel: Hashable, Sendable {
    /// Thermal voltage kT/q at 27 °C, the temperature SPICE simulates at by default.
    public static let thermalVoltage = 1.380649e-23 * 300.15 / 1.602176634e-19

    /// Above this many n·Vt the exponential continues as a straight line, so it cannot overflow.
    static let maxExponent = 80.0

    public var saturationCurrent: Double
    /// Emission coefficient n (ideality factor), typically between 1 and 2.
    public var emissionCoefficient: Double

    public init(saturationCurrent: Double, emissionCoefficient: Double = 1) {
        self.saturationCurrent = saturationCurrent
        self.emissionCoefficient = emissionCoefficient
    }

    /// n·Vt: the voltage over which the current grows by a factor of e.
    public var slopeVoltage: Double { emissionCoefficient * Self.thermalVoltage }

    /// Current and its slope dI/dV at voltage `v` (anode − cathode).
    public func evaluate(_ v: Double) -> (current: Double, conductance: Double) {
        let nvt = slopeVoltage
        guard v / nvt <= Self.maxExponent else {
            let e = exp(Self.maxExponent)
            let g = saturationCurrent * e / nvt
            return (saturationCurrent * (e - 1) + g * (v - Self.maxExponent * nvt), g)
        }
        let e = exp(v / nvt)
        return (saturationCurrent * (e - 1), saturationCurrent * e / nvt)
    }

    /// The voltage where the curve bends most sharply; Newton steps above it are limited.
    var criticalVoltage: Double {
        slopeVoltage * log(slopeVoltage / (2.squareRoot() * saturationCurrent))
    }

    /// Limits a Newton step from `old` to `new` (SPICE's pnjlim). Above the critical voltage the
    /// tangent overshoots by many decades of current, so the step instead follows the logarithm
    /// of the current the tangent asked for.
    func limit(_ new: Double, previous old: Double) -> Double {
        let nvt = slopeVoltage
        guard new > criticalVoltage, abs(new - old) > 2 * nvt else { return new }
        if old > 0 {
            let arg = 1 + (new - old) / nvt
            return arg > 0 ? old + nvt * log(arg) : criticalVoltage
        }
        return nvt * log(new / nvt)
    }
}

extension DiodeModel: NonlinearModel {
    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let (current, conductance) = evaluate(v[0])
        return ([current], [[conductance]])
    }

    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        [limit(new[0], previous: old[0])]
    }
}

// MARK: - BJT

/// Ebers–Moll bipolar transistor in SPICE's transport form, with the Early effect but no
/// high-injection or charge effects. For an NPN transistor, with forward and reverse junction
/// currents I_F = Is·(exp(V_BE/Vt) − 1) and I_R = Is·(exp(V_BC/Vt) − 1):
///
///     Ic = (I_F − I_R)·(1 − V_BC/V_A) − I_R/β_R
///     Ib = I_F/β_F + I_R/β_R
///
/// Both currents flow into the transistor; the emitter current is −(Ic + Ib). A PNP transistor
/// obeys the same laws with every voltage and current negated.
public struct BJTModel: Hashable, Sendable {
    /// Reverse current gain β_R, SPICE's default.
    public static let reverseBeta = 1.0
    /// A junction counts as forward-biased above this voltage when naming the region.
    static let junctionOnVoltage = 0.5

    public enum Region: String, Sendable {
        case cutoff
        case active = "forward active"
        case saturation
        case reverse = "reverse active"
    }

    public var polarity: TransistorParameters.Polarity
    /// Forward current gain β_F.
    public var beta: Double
    public var saturationCurrent: Double
    /// Early voltage V_A; 0 means no Early effect.
    public var earlyVoltage: Double

    public init(polarity: TransistorParameters.Polarity = .n, beta: Double, saturationCurrent: Double, earlyVoltage: Double = 0) {
        self.polarity = polarity
        self.beta = beta
        self.saturationCurrent = saturationCurrent
        self.earlyVoltage = earlyVoltage
    }

    /// Collector and base currents into the transistor at base–emitter and base–collector voltages.
    public func currents(vbe: Double, vbc: Double) -> (collector: Double, base: Double) {
        let currents = linearize(at: [vbe, vbc]).currents
        return (currents[0], currents[1])
    }

    public func region(vbe: Double, vbc: Double) -> Region {
        let s = polarity.sign
        switch (s * vbe > Self.junctionOnVoltage, s * vbc > Self.junctionOnVoltage) {
        case (true, false): return .active
        case (true, true): return .saturation
        case (false, true): return .reverse
        case (false, false): return .cutoff
        }
    }

    /// The NPN laws: currents [Ic, Ib] and their slopes with respect to [V_BE, V_BC].
    private func npn(vbe: Double, vbc: Double) -> (currents: [Double], jacobian: [[Double]]) {
        let junction = DiodeModel(saturationCurrent: saturationCurrent)
        let (forward, gForward) = junction.evaluate(vbe)
        let (reverse, gReverse) = junction.evaluate(vbc)
        let reverseBeta = Self.reverseBeta
        let early = earlyVoltage > 0 ? 1 - vbc / earlyVoltage : 1
        let earlySlope = earlyVoltage > 0 ? -1 / earlyVoltage : 0
        let transport = forward - reverse
        return (
            [transport * early - reverse / reverseBeta, forward / beta + reverse / reverseBeta],
            [
                [gForward * early, -gReverse * early + transport * earlySlope - gReverse / reverseBeta],
                [gForward / beta, gReverse / reverseBeta],
            ]
        )
    }
}

extension BJTModel: NonlinearModel {
    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let s = polarity.sign
        let (currents, jacobian) = npn(vbe: s * v[0], vbc: s * v[1])
        // Negating both voltages and currents leaves the slopes unchanged.
        return (currents.map { s * $0 }, jacobian)
    }

    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        let s = polarity.sign, junction = DiodeModel(saturationCurrent: saturationCurrent)
        return zip(new, old).map { s * junction.limit(s * $0, previous: s * $1) }
    }
}

// MARK: - MOSFET

/// Square-law MOSFET (SPICE level 1) with the body tied to the source. For an N-channel device
/// with overdrive V_ov = V_GS − V_th:
///
///     Id = 0                                  below threshold (V_ov ≤ 0)
///     Id = k·(V_ov·V_DS − V_DS²/2)·(1 + λ·V_DS)  in the triode region (V_DS < V_ov)
///     Id = ½·k·V_ov²·(1 + λ·V_DS)              in saturation
///
/// The drain current flows into the drain; the gate draws none. With V_DS < 0 the drain and
/// source swap roles. A P-channel device obeys the same laws with every voltage and current
/// negated, so it conducts when V_GS < −V_th.
public struct MOSFETModel: Hashable, Sendable {
    public enum Region: String, Sendable {
        case cutoff, triode, saturation
    }

    public var polarity: TransistorParameters.Polarity
    /// Threshold voltage V_th of the N-channel laws (its negative is a P-channel device's threshold).
    public var threshold: Double
    /// k = µ·Cox·W/L.
    public var transconductance: Double
    /// λ; 0 means no channel-length modulation.
    public var channelLengthModulation: Double

    public init(polarity: TransistorParameters.Polarity = .n, threshold: Double, transconductance: Double, channelLengthModulation: Double = 0) {
        self.polarity = polarity
        self.threshold = threshold
        self.transconductance = transconductance
        self.channelLengthModulation = channelLengthModulation
    }

    /// Drain current into the transistor at gate–source and drain–source voltages.
    public func drainCurrent(vgs: Double, vds: Double) -> Double {
        linearize(at: [vgs, vds]).currents[0]
    }

    public func region(vgs: Double, vds: Double) -> Region {
        let s = polarity.sign
        var (vgs, vds) = (s * vgs, s * vds)
        if vds < 0 { (vgs, vds) = (vgs - vds, -vds) }
        let overdrive = vgs - threshold
        if overdrive <= 0 { return .cutoff }
        return vds < overdrive ? .triode : .saturation
    }

    /// N-channel drain current with V_DS ≥ 0, and its slopes g_m = ∂Id/∂V_GS and g_ds = ∂Id/∂V_DS.
    private func forward(vgs: Double, vds: Double) -> (id: Double, gm: Double, gds: Double) {
        let k = transconductance, lambda = channelLengthModulation
        let overdrive = vgs - threshold
        guard overdrive > 0 else { return (0, 0, 0) }
        let modulation = 1 + lambda * vds
        if vds < overdrive {
            let core = overdrive * vds - vds * vds / 2
            return (k * core * modulation, k * vds * modulation, k * (overdrive - vds) * modulation + k * core * lambda)
        }
        let core = overdrive * overdrive / 2
        return (k * core * modulation, k * overdrive * modulation, k * core * lambda)
    }

    /// N-channel drain current at any V_DS: below zero, the drain and source swap roles.
    private func nChannel(vgs: Double, vds: Double) -> (id: Double, gm: Double, gds: Double) {
        guard vds < 0 else { return forward(vgs: vgs, vds: vds) }
        // Id(V_GS, V_DS) = −Id_forward(V_GS − V_DS, −V_DS).
        let swapped = forward(vgs: vgs - vds, vds: -vds)
        return (-swapped.id, -swapped.gm, swapped.gm + swapped.gds)
    }
}

extension MOSFETModel: NonlinearModel {
    func linearize(at v: [Double]) -> (currents: [Double], jacobian: [[Double]]) {
        let s = polarity.sign
        let (id, gm, gds) = nChannel(vgs: s * v[0], vds: s * v[1])
        return ([s * id], [[gm, gds]])
    }

    /// The square law cannot overshoot by decades the way an exponential does, so steps are not limited.
    func limitStep(_ new: [Double], from old: [Double]) -> [Double] {
        new
    }
}
