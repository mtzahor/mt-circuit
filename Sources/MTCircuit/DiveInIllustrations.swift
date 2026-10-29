import Charts
import CircuitCore
import SwiftUI

/// Drawings of the physics inside parts, for Dive In.
struct IllustrationView: View {
    let illustration: Illustration

    var body: some View {
        switch illustration {
        case .resistor: ResistorIllustration()
        case .capacitor: CapacitorIllustration()
        case .inductor: InductorIllustration()
        case .pnJunction: PNJunctionIllustration()
        case .diodeCurve: DiodeCurveIllustration()
        case .bjt: BJTIllustration()
        case .mosfet: MOSFETIllustration()
        case .cmosSwitches: CMOSSwitchesIllustration()
        }
    }
}

private enum Palette {
    /// p-type silicon and holes.
    static let p = Color(nsColor: .systemRed)
    /// n-type silicon and electrons.
    static let n = Color(nsColor: .systemBlue)
    static let metal = Color(nsColor: .systemGray)
    static let oxide = Color(nsColor: .systemYellow)
    static let copper = Color(nsColor: .systemOrange)
    static let resistive = Color(nsColor: .systemBrown)
    static let ink = Color.secondary
}

/// A repeatable pseudo-random number in 0..<1 for item `i`.
private func noise(_ i: Int, _ salt: Int) -> Double {
    let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return x - x.rounded(.down)
}

private func fraction(_ x: Double) -> Double { x - x.rounded(.down) }

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }

/// A canvas redrawn continuously, or drawn once when Reduce Motion is on. `draw` gets the time in seconds.
private struct AnimatedCanvas: View {
    let height: CGFloat
    let draw: (inout GraphicsContext, CGSize, Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(&context, size, timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(height: height)
    }
}

extension GraphicsContext {
    fileprivate func electron(at p: CGPoint, opacity: Double = 1) {
        fill(Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)), with: .color(Palette.n.opacity(opacity)))
    }

    fileprivate func hole(at p: CGPoint, opacity: Double = 1) {
        stroke(Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)),
               with: .color(Palette.p.opacity(opacity)), lineWidth: 1.3)
    }

    /// A fixed charged atom: a square with its sign.
    fileprivate func ion(at p: CGPoint, positive: Bool) {
        let color = (positive ? Palette.n : Palette.p).opacity(0.75)
        stroke(Path(CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(color), lineWidth: 1)
        var sign = Path()
        sign.move(to: CGPoint(x: p.x - 2.5, y: p.y))
        sign.addLine(to: CGPoint(x: p.x + 2.5, y: p.y))
        if positive {
            sign.move(to: CGPoint(x: p.x, y: p.y - 2.5))
            sign.addLine(to: CGPoint(x: p.x, y: p.y + 2.5))
        }
        stroke(sign, with: .color(color), lineWidth: 1)
    }

    fileprivate func label(_ text: String, at p: CGPoint, anchor: UnitPoint = .center, font: Font = .caption, color: Color = Palette.ink) {
        draw(Text(text).font(font).foregroundColor(color), at: p, anchor: anchor)
    }

    fileprivate func line(_ a: CGPoint, _ b: CGPoint, color: Color = Palette.ink, width: CGFloat = 1.2, dash: [CGFloat] = []) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }

    fileprivate func arrow(_ a: CGPoint, _ b: CGPoint, color: Color = Palette.ink, width: CGFloat = 1.3) {
        line(a, b, color: color, width: width)
        let angle = atan2(b.y - a.y, b.x - a.x), size: CGFloat = 6
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - size * cos(angle - .pi / 7), y: b.y - size * sin(angle - .pi / 7)))
        head.addLine(to: CGPoint(x: b.x - size * cos(angle + .pi / 7), y: b.y - size * sin(angle + .pi / 7)))
        head.closeSubpath()
        fill(head, with: .color(color))
    }

    /// A dimension line with arrowheads at both ends and a label at its middle.
    fileprivate func dimension(_ a: CGPoint, _ b: CGPoint, _ text: String, labelOffset: CGVector) {
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        arrow(middle, a, width: 1)
        arrow(middle, b, width: 1)
        label(text, at: CGPoint(x: middle.x + labelOffset.dx, y: middle.y + labelOffset.dy), font: .callout.italic())
    }
}

/// Symbols for the particles in an illustration, with their meaning.
private struct Legend: View {
    enum Symbol { case electron, hole, ion, atom }

    let items: [(Symbol, String)]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        switch item.0 {
                        case .electron: context.electron(at: center)
                        case .hole: context.hole(at: center)
                        case .ion: context.ion(at: center, positive: false)
                        case .atom: Self.atom(context, at: center)
                        }
                    }
                    .frame(width: 11, height: 11)
                    Text(item.1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    static func atom(_ context: GraphicsContext, at p: CGPoint) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(Palette.metal.opacity(0.4)))
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Resistor

private struct ResistorIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            AnimatedCanvas(height: 170, draw: Self.draw)
            Legend(items: [(.atom, "atom of the material"), (.electron, "free electron, drifting against the current")])
        }
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        // A see-through cylinder: its near end is the cross-section A, its far end dashed.
        let body = CGRect(x: 70, y: 56, width: max(120, size.width - 140), height: 66)
        let face = CGRect(x: body.minX - 13, y: body.minY, width: 26, height: body.height)
        let back = face.offsetBy(dx: body.width, dy: 0)
        context.line(CGPoint(x: 20, y: body.midY), CGPoint(x: face.minX, y: body.midY), width: 2)
        context.line(CGPoint(x: back.maxX, y: body.midY), CGPoint(x: size.width - 20, y: body.midY), width: 2)
        context.fill(Path(body), with: .color(Palette.resistive.opacity(0.16)))
        context.stroke(Path(ellipseIn: back), with: .color(Palette.resistive.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        for y in [body.minY, body.maxY] {
            context.line(CGPoint(x: body.minX, y: y), CGPoint(x: body.maxX, y: y), color: Palette.resistive.opacity(0.6))
        }

        // Atoms vibrate in place; electrons zigzag slowly to the left between collisions.
        let columns = Int(body.width / 28), rows = 3
        for column in 0..<columns {
            for row in 0..<rows {
                let i = column * rows + row
                let x = body.minX + (CGFloat(column) + 0.5) * body.width / CGFloat(columns) + 1.5 * sin(t * 9 + noise(i, 4) * 6)
                let y = body.minY + (CGFloat(row) + 0.5) * body.height / CGFloat(rows) + 1.5 * cos(t * 8 + noise(i, 5) * 6)
                Legend.atom(context, at: CGPoint(x: x, y: y))
            }
        }
        for i in 0..<22 {
            let progress = fraction(noise(i, 1) + 0.04 * t)
            let x = lerp(body.maxX, body.minX, progress)
            let bounce = abs(fraction(progress * 7 + noise(i, 3)) - 0.5) * 2
            let y = body.minY + 8 + (body.height - 16) * (0.2 + 0.6 * noise(i, 2)) + 9 * (bounce - 0.5)
            context.electron(at: CGPoint(x: x, y: y), opacity: min(1, min(progress, 1 - progress) * 12))
        }

        context.fill(Path(ellipseIn: face), with: .color(Palette.resistive.opacity(0.32)))
        context.stroke(Path(ellipseIn: face), with: .color(Palette.resistive.opacity(0.6)), lineWidth: 1.2)
        context.label("A", at: CGPoint(x: face.midX, y: face.minY - 12), font: .callout.italic())
        context.arrow(CGPoint(x: body.midX - 40, y: 24), CGPoint(x: body.midX + 40, y: 24), color: .primary)
        context.label("current I", at: CGPoint(x: body.midX + 48, y: 24), anchor: .leading)
        context.dimension(CGPoint(x: body.minX, y: body.maxY + 22), CGPoint(x: body.maxX, y: body.maxY + 22), "L",
                          labelOffset: CGVector(dx: 0, dy: 13))
    }
}

// MARK: - Capacitor

private struct CapacitorIllustration: View {
    var body: some View {
        Canvas { context, size in Self.draw(&context, size) }
            .frame(height: 210)
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let width = min(320, size.width * 0.55), center = size.width / 2
        let top = CGRect(x: center - width / 2, y: 58, width: width, height: 8)
        let bottom = CGRect(x: top.minX, y: 144, width: width, height: 8)
        let gap = CGRect(x: top.minX, y: top.maxY, width: width, height: bottom.minY - top.maxY)
        context.fill(Path(gap), with: .color(Palette.oxide.opacity(0.14)))
        context.line(CGPoint(x: center, y: 16), CGPoint(x: center, y: top.minY), width: 2)
        context.line(CGPoint(x: center, y: bottom.maxY), CGPoint(x: center, y: size.height - 14), width: 2)
        for plate in [top, bottom] {
            context.fill(Path(roundedRect: plate, cornerRadius: 2), with: .color(Palette.metal.opacity(0.75)))
        }
        let count = Int(width / 34)
        for i in 0..<count {
            let x = top.minX + (CGFloat(i) + 0.5) * width / CGFloat(count)
            context.label("+", at: CGPoint(x: x, y: top.maxY + 9), font: .body.weight(.bold), color: Palette.p)
            context.label("−", at: CGPoint(x: x, y: bottom.minY - 10), font: .body.weight(.bold), color: Palette.n)
            if i > 0 {
                let fieldX = top.minX + CGFloat(i) * width / CGFloat(count)
                context.arrow(CGPoint(x: fieldX, y: top.maxY + 16), CGPoint(x: fieldX, y: bottom.minY - 16), color: Palette.ink.opacity(0.6), width: 1)
            }
        }
        context.label("+", at: CGPoint(x: center + 14, y: 26), font: .title3.weight(.semibold))
        context.label("−", at: CGPoint(x: center + 14, y: size.height - 26), font: .title3.weight(.semibold))
        context.label("plate area A", at: CGPoint(x: top.maxX, y: top.minY - 12), anchor: .trailing)
        context.label("dielectric", at: CGPoint(x: gap.minX - 12, y: gap.midY - 9), anchor: .trailing)
        context.label("electric field", at: CGPoint(x: gap.minX - 12, y: gap.midY + 9), anchor: .trailing)
        context.dimension(CGPoint(x: gap.maxX + 22, y: top.maxY), CGPoint(x: gap.maxX + 22, y: bottom.minY), "d",
                          labelOffset: CGVector(dx: 12, dy: 0))
    }
}

// MARK: - Inductor

private struct InductorIllustration: View {
    var body: some View {
        Canvas { context, size in Self.draw(&context, size) }
            .frame(height: 260)
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let turns = 7, centerY: CGFloat = 130, radius: CGFloat = 42
        let length = min(300, size.width * 0.5), x0 = size.width / 2 - length / 2, x1 = x0 + length
        let pitch = length / CGFloat(turns)

        // Field lines: straight through the coil, returning around the outside.
        let field = Palette.n.opacity(0.55)
        for (rx, ry) in [(length / 2 + 70, 94.0), (length / 2 + 110, 118.0)] {
            let ellipse = Path(ellipseIn: CGRect(x: size.width / 2 - rx, y: centerY - ry, width: 2 * rx, height: 2 * ry))
            context.stroke(ellipse, with: .color(field), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            context.arrow(CGPoint(x: size.width / 2 + 6, y: centerY - ry), CGPoint(x: size.width / 2 - 6, y: centerY - ry), color: field)
            context.arrow(CGPoint(x: size.width / 2 + 6, y: centerY + ry), CGPoint(x: size.width / 2 - 6, y: centerY + ry), color: field)
        }
        for dy in [-18.0, 0, 18] {
            context.arrow(CGPoint(x: x0 - 30, y: centerY + dy), CGPoint(x: x1 + 40, y: centerY + dy), color: field)
        }

        // Each turn's far half is faint and its near half solid.
        for i in 0..<turns {
            let x = x0 + (CGFloat(i) + 0.5) * pitch
            let loop = CGRect(x: x - pitch * 0.45, y: centerY - radius, width: pitch * 0.9, height: 2 * radius)
            var far = Path(), near = Path()
            far.addArc(center: .zero, radius: 1, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            near.addArc(center: .zero, radius: 1, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            let transform = CGAffineTransform(translationX: loop.midX, y: loop.midY).scaledBy(x: loop.width / 2, y: loop.height / 2)
            context.stroke(far.applying(transform), with: .color(Palette.copper.opacity(0.35)), lineWidth: 2)
            context.stroke(near.applying(transform), with: .color(Palette.copper), lineWidth: 3)
        }
        context.line(CGPoint(x: x0 - 50, y: centerY + radius), CGPoint(x: x0 + pitch / 2, y: centerY + radius), color: Palette.copper, width: 3)
        context.line(CGPoint(x: x1 - pitch / 2, y: centerY + radius), CGPoint(x: x1 + 50, y: centerY + radius), color: Palette.copper, width: 3)
        context.arrow(CGPoint(x: x0 - 46, y: centerY + radius + 12), CGPoint(x: x0 - 14, y: centerY + radius + 12), color: .primary)
        context.label("I", at: CGPoint(x: x0 - 30, y: centerY + radius + 24), font: .callout.italic())

        context.label("N turns", at: CGPoint(x: size.width / 2, y: centerY - radius - 12))
        context.label("magnetic field", at: CGPoint(x: size.width / 2, y: centerY - 105), color: Palette.n)
        context.dimension(CGPoint(x: x0, y: centerY + radius + 18), CGPoint(x: x1, y: centerY + radius + 18), "ℓ",
                          labelOffset: CGVector(dx: 0, dy: 11))
    }
}

// MARK: - pn junction

private struct PNJunctionIllustration: View {
    enum Bias: String, CaseIterable {
        case none = "No Bias"
        case forward = "Forward"
        case reverse = "Reverse"
    }

    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let bias = State(initialValue: Bias.none)

    var body: some View {
        let bias = self.bias.wrappedValue
        VStack(spacing: 12) {
            Picker("Bias", selection: self.bias.projectedValue) {
                ForEach(Bias.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            AnimatedCanvas(height: 218) { context, size, t in Self.draw(&context, size, t, bias: bias) }
            Legend(items: [(.hole, "hole"), (.electron, "free electron"), (.ion, "fixed charged atom")])
            Caption(Self.caption(bias))
        }
    }

    private static func caption(_ bias: Bias) -> String {
        switch bias {
        case .none: "Without bias, the barrier built by diffusion holds the carriers back: no current flows."
        case .forward: "Forward bias shrinks the depletion region. Carriers flood across the junction and recombine on the other side: current flows."
        case .reverse: "Reverse bias pulls the carriers away from the junction and widens the depletion region: only a tiny leakage current flows."
        }
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double, bias: Bias) {
        let bar = CGRect(x: 30, y: 34, width: size.width - 60, height: 104)
        let middle = bar.midX
        let half = bar.width * (bias == .forward ? 0.025 : bias == .reverse ? 0.15 : 0.075)

        context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: middle - bar.minX, height: bar.height)), with: .color(Palette.p.opacity(0.13)))
        context.fill(Path(CGRect(x: middle, y: bar.minY, width: bar.maxX - middle, height: bar.height)), with: .color(Palette.n.opacity(0.13)))
        let depletion = CGRect(x: middle - half, y: bar.minY, width: 2 * half, height: bar.height)
        context.fill(Path(depletion), with: .color(Color(nsColor: .textBackgroundColor).opacity(0.6)))
        for x in [depletion.minX, depletion.maxX] {
            context.line(CGPoint(x: x, y: bar.minY), CGPoint(x: x, y: bar.maxY), width: 1, dash: [3, 3])
        }
        context.stroke(Path(roundedRect: bar, cornerRadius: 4), with: .color(Palette.ink.opacity(0.5)), lineWidth: 1)

        // The fixed atoms left charged in the depletion region: negative on the p side, positive on the n side.
        let columns = max(1, Int(half / 13)), rows = 5
        for side in [-1.0, 1.0] {
            for column in 0..<columns {
                for row in 0..<rows {
                    let x = middle + side * half * (CGFloat(column) + 0.5) / CGFloat(columns)
                    let y = bar.minY + bar.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                    context.ion(at: CGPoint(x: x, y: y), positive: side > 0)
                }
            }
        }

        // Holes on the p side and electrons on the n side. With forward bias they stream toward the
        // junction and fade out on the far side, where they recombine.
        let overshoot = bar.width * 0.08
        for i in 0..<34 {
            for isHole in [true, false] {
                let salt = isHole ? 0 : 10
                let u = noise(i, salt + 1), phase = noise(i, salt + 3) * 6.3
                let y = bar.minY + 8 + (bar.height - 16) * noise(i, salt + 2) + 2 * sin(t * 2.3 + phase)
                let outer = isHole ? bar.minX + 6 : bar.maxX - 6
                let edge = isHole ? middle - half - 6 : middle + half + 6
                var x: CGFloat, opacity = 1.0
                if bias == .forward {
                    let end = isHole ? middle + half + overshoot : middle - half - overshoot
                    let progress = fraction(u + 0.1 * t)
                    x = lerp(outer, end, progress)
                    let past = isHole ? x - (middle + half) : (middle - half) - x
                    opacity = min(1, progress * 15, max(0, 1 - past / overshoot))
                } else {
                    x = lerp(outer, edge, u) + 2.5 * sin(t * 1.7 + phase)
                }
                if isHole {
                    context.hole(at: CGPoint(x: x, y: y), opacity: opacity)
                } else {
                    context.electron(at: CGPoint(x: x, y: y), opacity: opacity)
                }
            }
        }

        context.label("p-type · anode", at: CGPoint(x: (bar.minX + middle) / 2, y: 16), font: .caption.weight(.semibold), color: Palette.p)
        context.label("n-type · cathode", at: CGPoint(x: (middle + bar.maxX) / 2, y: 16), font: .caption.weight(.semibold), color: Palette.n)
        context.label("depletion region", at: CGPoint(x: middle, y: bar.maxY + 14))

        guard bias != .none else { return }
        // The bias battery: its longer plate is the + terminal, on the anode side for forward bias.
        let y = bar.maxY + 52, left = bar.minX + 14, right = bar.maxX - 14
        context.line(CGPoint(x: left, y: bar.maxY), CGPoint(x: left, y: y))
        context.line(CGPoint(x: right, y: bar.maxY), CGPoint(x: right, y: y))
        context.line(CGPoint(x: left, y: y), CGPoint(x: middle - 5, y: y))
        context.line(CGPoint(x: middle + 5, y: y), CGPoint(x: right, y: y))
        let plus: CGFloat = bias == .forward ? -5 : 5
        context.line(CGPoint(x: middle + plus, y: y - 13), CGPoint(x: middle + plus, y: y + 13), color: .primary, width: 1.6)
        context.line(CGPoint(x: middle - plus, y: y - 7), CGPoint(x: middle - plus, y: y + 7), color: .primary, width: 3)
        context.label("+", at: CGPoint(x: middle + 3 * plus, y: y - 16), font: .callout.weight(.semibold))
        context.label("−", at: CGPoint(x: middle - 3 * plus, y: y - 16), font: .callout.weight(.semibold))
        if bias == .forward {
            for x in [left + 50, right - 50] {
                context.arrow(CGPoint(x: x + 14, y: y), CGPoint(x: x - 14, y: y), color: .primary)
            }
            context.label("I", at: CGPoint(x: left + 50, y: y - 12), font: .callout.italic())
        }
    }
}

// MARK: - Diode curve

private struct DiodeCurveIllustration: View {
    private struct Point: Identifiable {
        let voltage: Double
        let milliamps: Double
        var id: Double { voltage }
    }

    private static let points: [Point] = {
        let model = DiodeModel(saturationCurrent: ComponentKind.diode.defaultValue)
        return stride(from: -0.3, through: 0.75, by: 0.005).map { Point(voltage: $0, milliamps: model.evaluate($0).current * 1e3) }
    }()

    var body: some View {
        VStack(spacing: 8) {
            Chart(Self.points) { point in
                LineMark(x: .value("Voltage", point.voltage), y: .value("Current", point.milliamps))
                    .foregroundStyle(Palette.n)
                    .interpolationMethod(.monotone)
            }
            .chartXAxisLabel("Voltage across the diode (V)")
            .chartYAxisLabel("Current (mA)")
            .chartXScale(domain: -0.3...0.75)
            .chartYScale(domain: -2...40)
            .frame(height: 190)
            Caption("The default diode in MT Circuit (Is = 10 fA): nothing flows in reverse, and the current takes off above about 0.6 V.")
        }
    }
}

// MARK: - BJT

private struct BJTIllustration: View {
    var body: some View {
        VStack(spacing: 12) {
            AnimatedCanvas(height: 220, draw: Self.draw)
            Legend(items: [(.electron, "free electron"), (.hole, "hole")])
            Caption("Electrons from the emitter cross the thin base and are swept into the collector. The few that recombine in the base make up the base current.")
        }
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let bar = CGRect(x: 54, y: 72, width: size.width - 108, height: 92)
        let emitterEnd = bar.minX + bar.width * 0.36, baseEnd = emitterEnd + bar.width * 0.1
        let baseMiddle = (emitterEnd + baseEnd) / 2
        context.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: emitterEnd - bar.minX, height: bar.height)), with: .color(Palette.n.opacity(0.24)))
        context.fill(Path(CGRect(x: emitterEnd, y: bar.minY, width: baseEnd - emitterEnd, height: bar.height)), with: .color(Palette.p.opacity(0.16)))
        context.fill(Path(CGRect(x: baseEnd, y: bar.minY, width: bar.maxX - baseEnd, height: bar.height)), with: .color(Palette.n.opacity(0.12)))
        context.stroke(Path(roundedRect: bar, cornerRadius: 4), with: .color(Palette.ink.opacity(0.5)), lineWidth: 1)

        context.line(CGPoint(x: bar.minX, y: bar.midY), CGPoint(x: bar.minX - 22, y: bar.midY), width: 2)
        context.line(CGPoint(x: bar.maxX, y: bar.midY), CGPoint(x: bar.maxX + 22, y: bar.midY), width: 2)
        context.line(CGPoint(x: baseMiddle, y: bar.minY), CGPoint(x: baseMiddle, y: bar.minY - 34), width: 2)
        context.label("E", at: CGPoint(x: bar.minX - 34, y: bar.midY), font: .headline)
        context.label("C", at: CGPoint(x: bar.maxX + 34, y: bar.midY), font: .headline)
        context.label("B", at: CGPoint(x: baseMiddle, y: bar.minY - 46), font: .headline)
        context.label("emitter (n+)", at: CGPoint(x: (bar.minX + emitterEnd) / 2, y: bar.minY + 12), font: .caption.weight(.semibold), color: Palette.n)
        context.label("collector (n)", at: CGPoint(x: (baseEnd + bar.maxX) / 2, y: bar.minY + 12), font: .caption.weight(.semibold), color: Palette.n)
        context.label("base (p)", at: CGPoint(x: baseMiddle + 10, y: bar.minY - 18), anchor: .leading, font: .caption.weight(.semibold), color: Palette.p)

        for i in 0..<6 {
            let x = emitterEnd + 6 + (baseEnd - emitterEnd - 12) * noise(i, 7) + 1.5 * sin(t * 2 + Double(i))
            let y = bar.minY + 24 + (bar.height - 32) * noise(i, 8)
            context.hole(at: CGPoint(x: x, y: y))
        }
        // One electron in nine recombines in the base and leaves through the base lead.
        for i in 0..<40 {
            let progress = fraction(noise(i, 1) + 0.15 * t)
            let y = bar.minY + 24 + (bar.height - 32) * noise(i, 2)
            let start = bar.minX + 6, end = bar.maxX - 6
            let point: CGPoint
            if i % 9 == 0 {
                let turn = 0.55
                if progress < turn {
                    point = CGPoint(x: lerp(start, baseMiddle, progress / turn), y: y)
                } else {
                    point = CGPoint(x: baseMiddle, y: lerp(y, bar.minY - 30, (progress - turn) / (1 - turn)))
                }
            } else {
                point = CGPoint(x: lerp(start, end, progress), y: y)
            }
            context.electron(at: point, opacity: min(1, progress * 15, (1 - progress) * 15))
        }

        context.line(CGPoint(x: emitterEnd, y: bar.maxY), CGPoint(x: emitterEnd, y: bar.maxY + 14), width: 1)
        context.line(CGPoint(x: baseEnd, y: bar.maxY), CGPoint(x: baseEnd, y: bar.maxY + 34), width: 1)
        context.label("forward-biased by about 0.7 V", at: CGPoint(x: emitterEnd - 4, y: bar.maxY + 20), anchor: .trailing)
        context.label("reverse-biased", at: CGPoint(x: baseEnd + 4, y: bar.maxY + 40), anchor: .leading)
    }
}

// MARK: - MOSFET

private struct MOSFETIllustration: View {
    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let gateVoltage = State(initialValue: 0.0)
    private static let threshold = ComponentKind.mosfet.defaultValue
    private static let model = MOSFETModel(threshold: threshold, transconductance: TransistorParameters().transconductance)

    var body: some View {
        let vgs = gateVoltage.wrappedValue
        VStack(spacing: 12) {
            AnimatedCanvas(height: 236) { context, size, t in Self.draw(&context, size, t, vgs: vgs) }
            HStack(spacing: 10) {
                Text("Gate voltage VGS")
                Slider(value: gateVoltage.projectedValue, in: 0...3)
                Text(SIFormat.string(vgs, unit: "V", significantDigits: 2))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(maxWidth: 440)
            Legend(items: [(.electron, "free electron"), (.hole, "hole")])
            Caption(vgs < Self.threshold
                ? "Below the threshold of \(SIFormat.string(Self.threshold, unit: "V")), the gate's field only pushes holes away: there's no channel, and no current flows from drain to source."
                : "A channel of electrons joins the source and the drain. In saturation, Id = ½ · k · (VGS − Vth)² = \(SIFormat.string(Self.model.drainCurrent(vgs: vgs, vds: 10), unit: "A", significantDigits: 2)).")
        }
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ t: Double, vgs: Double) {
        let body = CGRect(x: 30, y: 98, width: size.width - 60, height: 118)
        let wellWidth = body.width * 0.24, wellHeight: CGFloat = 46
        let source = CGRect(x: body.minX + 18, y: body.minY, width: wellWidth, height: wellHeight)
        let drain = CGRect(x: body.maxX - 18 - wellWidth, y: body.minY, width: wellWidth, height: wellHeight)
        let oxide = CGRect(x: source.maxX - 10, y: body.minY - 7, width: drain.minX - source.maxX + 20, height: 7)
        let gate = CGRect(x: oxide.minX, y: oxide.minY - 24, width: oxide.width, height: 24)
        let well = UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)

        context.fill(Path(body), with: .color(Palette.p.opacity(0.13)))
        context.stroke(Path(body), with: .color(Palette.ink.opacity(0.4)), lineWidth: 1)
        for rect in [source, drain] {
            context.fill(well.path(in: rect), with: .color(Palette.n.opacity(0.26)))
            context.label("n+", at: CGPoint(x: rect.midX, y: rect.maxY - 12), font: .caption.weight(.semibold), color: Palette.n)
        }
        context.fill(Path(oxide), with: .color(Palette.oxide.opacity(0.55)))
        context.fill(Path(roundedRect: gate, cornerRadius: 2), with: .color(Palette.metal.opacity(0.55)))
        context.label("p-type body", at: CGPoint(x: body.midX, y: body.maxY - 12), font: .caption.weight(.semibold), color: Palette.p)
        context.label("oxide", at: CGPoint(x: oxide.maxX + 6, y: oxide.midY - 2), anchor: .leading)

        for (rect, name) in [(source, "Source"), (gate, "Gate"), (drain, "Drain")] {
            context.line(CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: 28), width: 2)
            context.label(name, at: CGPoint(x: rect.midX, y: 16), font: .callout.weight(.semibold))
        }

        // The gate's positive charge grows with its voltage.
        let charges = Int((vgs / 3 * 9).rounded())
        for i in 0..<charges {
            let x = gate.minX + (CGFloat(i) + 0.5) * gate.width / CGFloat(max(charges, 1))
            context.label("+", at: CGPoint(x: x, y: gate.maxY - 8), font: .caption.weight(.bold), color: Palette.p)
        }

        // The field pushes holes away from the surface under the gate, deeper as VGS rises.
        let cleared = 34 * min(vgs, threshold) / threshold + 8 * max(0, min(1, (vgs - threshold) / 2))
        for i in 0..<56 {
            let x = body.minX + 8 + (body.width - 16) * noise(i, 1) + 2 * sin(t * 1.9 + noise(i, 3) * 6)
            let y = body.minY + 8 + (body.height - 30) * noise(i, 2) + 2 * cos(t * 1.6 + noise(i, 4) * 6)
            let inWell = [source, drain].contains { $0.insetBy(dx: -5, dy: -5).contains(CGPoint(x: x, y: y)) }
            let underGate = x > source.maxX && x < drain.minX && y < body.minY + cleared
            if !inWell && !underGate { context.hole(at: CGPoint(x: x, y: y)) }
        }
        for rect in [source, drain] {
            for i in 0..<10 {
                let x = rect.minX + 10 + (rect.width - 20) * noise(i, rect == source ? 5 : 6) + 1.5 * sin(t * 2 + Double(i))
                let y = rect.minY + 8 + (rect.height - 26) * noise(i, rect == source ? 7 : 8)
                context.electron(at: CGPoint(x: x, y: y))
            }
        }

        guard vgs > threshold else { return }
        let strength = min(1, (vgs - threshold) / 2)
        let channel = CGRect(x: source.maxX - 6, y: body.minY, width: drain.minX - source.maxX + 12, height: 3 + 7 * strength)
        context.fill(Path(channel), with: .color(Palette.n.opacity(0.4)))
        for i in 0..<Int(4 + 14 * strength) {
            let progress = fraction(noise(i, 9) + 0.2 * t)
            let x = lerp(source.midX, drain.midX, progress)
            let y = x < source.maxX || x > drain.minX ? body.minY + 6 : channel.midY + (noise(i, 10) - 0.5) * channel.height * 0.6
            context.electron(at: CGPoint(x: x, y: y), opacity: min(1, progress * 12, (1 - progress) * 12))
        }
    }
}

// MARK: - CMOS switches

/// A CMOS gate's transistors drawn as switches between the supply, the output, and ground, for
/// inputs the reader sets. P-channel transistors (red) close when their input is 0, n-channel ones
/// (blue) when it is 1.
private struct CMOSSwitchesIllustration: View {
    enum Gate: String, CaseIterable {
        case not = "NOT", nand = "NAND", nor = "NOR"
    }

    /// A transistor as a switch from height `top` to `bottom` at horizontal offset `x` from the center.
    private struct Switch {
        var pChannel: Bool
        var input: Int
        var x: CGFloat
        var top: CGFloat
        var bottom: CGFloat

        func isClosed(_ inputs: [Bool]) -> Bool { inputs[input] != pChannel }
    }

    // State is declared explicitly: the @State macro's plugin ships only with Xcode, not the Command Line Tools.
    private let gate = State(initialValue: Gate.nand)
    private let inputs = State(initialValue: [true, false])

    private static let supplyY: CGFloat = 26, outputY: CGFloat = 128, groundY: CGFloat = 230

    var body: some View {
        let gate = self.gate.wrappedValue, inputs = self.inputs.wrappedValue
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Picker("Gate", selection: self.gate.projectedValue) {
                    ForEach(Gate.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                ForEach(0..<(gate == .not ? 1 : 2), id: \.self) { index in
                    Button("\(["A", "B"][index]) = \(inputs[index] ? 1 : 0)") { self.inputs.wrappedValue[index].toggle() }
                        .monospacedDigit()
                        .help("Switch input \(["A", "B"][index])")
                }
            }
            Canvas { context, size in Self.draw(&context, size, gate: gate, inputs: inputs) }
                .frame(height: 256)
            Text("p: p-channel MOSFET, on when its input is 0.   n: n-channel MOSFET, on when its input is 1.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Caption(Self.caption(gate, output: Self.pullUpConducts(gate, inputs)))
        }
    }

    private static func switches(_ gate: Gate) -> [Switch] {
        let middleUp = (supplyY + outputY) / 2, middleDown = (outputY + groundY) / 2
        switch gate {
        case .not:
            return [Switch(pChannel: true, input: 0, x: 0, top: supplyY, bottom: outputY),
                    Switch(pChannel: false, input: 0, x: 0, top: outputY, bottom: groundY)]
        case .nand:
            return [Switch(pChannel: true, input: 0, x: -50, top: supplyY, bottom: outputY),
                    Switch(pChannel: true, input: 1, x: 50, top: supplyY, bottom: outputY),
                    Switch(pChannel: false, input: 0, x: 0, top: outputY, bottom: middleDown),
                    Switch(pChannel: false, input: 1, x: 0, top: middleDown, bottom: groundY)]
        case .nor:
            return [Switch(pChannel: true, input: 0, x: 0, top: supplyY, bottom: middleUp),
                    Switch(pChannel: true, input: 1, x: 0, top: middleUp, bottom: outputY),
                    Switch(pChannel: false, input: 0, x: -50, top: outputY, bottom: groundY),
                    Switch(pChannel: false, input: 1, x: 50, top: outputY, bottom: groundY)]
        }
    }

    /// Whether the pull-up network connects the output to the supply: its switches in parallel for
    /// NAND, in series for NOR. The pull-down network conducts exactly when it doesn't.
    private static func pullUpConducts(_ gate: Gate, _ inputs: [Bool]) -> Bool {
        let up = switches(gate).filter(\.pChannel).map { $0.isClosed(inputs) }
        return gate == .nor ? up.allSatisfy { $0 } : up.contains(true)
    }

    private static func caption(_ gate: Gate, output: Bool) -> String {
        let state = output
            ? "Y = 1: the pull-up network connects the output to the supply, and the pull-down network is open."
            : "Y = 0: the pull-down network connects the output to ground, and the pull-up network is open."
        switch gate {
        case .not: return state + " One transistor is always off, so no current flows from the supply to ground."
        case .nand: return state + " The pull-down transistors are in series: only A = 1 and B = 1 together connect the output to ground."
        case .nor: return state + " The pull-up transistors are in series: only A = 0 and B = 0 together connect the output to the supply."
        }
    }

    static func draw(_ context: inout GraphicsContext, _ size: CGSize, gate: Gate, inputs: [Bool]) {
        let center = size.width / 2 - 30
        let high = Palette.p, low = Palette.n
        let output = pullUpConducts(gate, inputs)
        let all = switches(gate)

        // Rails and the output node, which spans the parallel branches.
        let span = all.map(\.x).max() ?? 0
        context.line(CGPoint(x: center - span - 30, y: supplyY), CGPoint(x: center + span + 30, y: supplyY), color: high, width: 2.5)
        context.label("supply, 5 V", at: CGPoint(x: center + span + 40, y: supplyY), anchor: .leading, color: high)
        context.line(CGPoint(x: center - span - 30, y: groundY), CGPoint(x: center + span + 30, y: groundY), color: low, width: 2.5)
        context.label("ground, 0 V", at: CGPoint(x: center + span + 40, y: groundY), anchor: .leading, color: low)
        let level = output ? high : low
        context.line(CGPoint(x: center - span, y: outputY), CGPoint(x: center + span + 70, y: outputY), color: level, width: 2)
        context.fill(Path(ellipseIn: CGRect(x: center + span + 66, y: outputY - 5, width: 10, height: 10)), with: .color(level))
        context.label("Y = \(output ? 1 : 0)", at: CGPoint(x: center + span + 84, y: outputY), anchor: .leading,
                      font: .title3.weight(.semibold).monospacedDigit(), color: level)

        // A switch conducts toward the output when it and the rest of its network do.
        let pullUp = output, pullDown = !output
        for item in all {
            let x = center + item.x
            let closed = item.isClosed(inputs)
            let live = closed && (item.pChannel ? pullUp : pullDown)
            let color = item.pChannel ? high : low
            let ink = live ? color : Palette.ink
            let width: CGFloat = live ? 2.2 : 1.3
            let middle = (item.top + item.bottom) / 2
            let upper = CGPoint(x: x, y: middle - 13), lower = CGPoint(x: x, y: middle + 13)
            context.line(CGPoint(x: x, y: item.top), upper, color: ink, width: width)
            context.line(lower, CGPoint(x: x, y: item.bottom), color: ink, width: width)
            context.line(lower, closed ? upper : CGPoint(x: x - 15, y: middle - 9), color: closed ? ink : Palette.ink, width: width)
            for contact in [upper, lower] {
                context.fill(Path(ellipseIn: CGRect(x: contact.x - 2.5, y: contact.y - 2.5, width: 5, height: 5)), with: .color(ink))
            }
            let input = ["A", "B"][item.input]
            context.label("\(item.pChannel ? "p" : "n") · \(input) = \(inputs[item.input] ? 1 : 0)",
                          at: CGPoint(x: x + 10, y: middle - 6), anchor: .leading, font: .caption.weight(.semibold), color: color)
            context.label(closed ? "on" : "off", at: CGPoint(x: x + 10, y: middle + 8), anchor: .leading)
        }
        context.label("pull-up", at: CGPoint(x: center - span - 36, y: (supplyY + outputY) / 2), anchor: .trailing, color: high)
        context.label("pull-down", at: CGPoint(x: center - span - 36, y: (outputY + groundY) / 2), anchor: .trailing, color: low)
    }
}
