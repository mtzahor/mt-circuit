// Renders the MT Circuit app icon into an .iconset directory.
// Usage: swift scripts/render-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)
    // Flip so y grows downward, like the schematic.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Background tile.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        CGColor(srgbRed: 0.13, green: 0.18, blue: 0.29, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.08, blue: 0.14, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Grid dots.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.13))
    for x in stride(from: 148, through: 900, by: 48) {
        for y in stride(from: 148, through: 900, by: 48) {
            ctx.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
        }
    }

    // Resistor across the top.
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineWidth(26)
    ctx.move(to: CGPoint(x: 200, y: 380))
    ctx.addLine(to: CGPoint(x: 330, y: 380))
    for i in 0..<6 {
        let x = 330 + CGFloat(2 * i + 1) * 364 / 12
        ctx.addLine(to: CGPoint(x: x, y: i.isMultiple(of: 2) ? 320 : 440))
    }
    ctx.addLine(to: CGPoint(x: 694, y: 380))
    ctx.addLine(to: CGPoint(x: 824, y: 380))
    ctx.strokePath()

    // Damped oscillation (RLC ringing) below it.
    ctx.setStrokeColor(CGColor(srgbRed: 0.30, green: 0.82, blue: 0.56, alpha: 1))
    ctx.setLineWidth(22)
    for i in 0...300 {
        let t = CGFloat(i) / 300
        let x = 200 + t * 624
        let y = 680 - 150 * exp(-3.2 * t) * cos(t * 2 * .pi * 3.2)
        if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
    }
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: base * scale).write(to: output.appendingPathComponent(name))
    }
}
