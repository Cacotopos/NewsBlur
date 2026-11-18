import AppKit
import CoreGraphics
import CoreText

// Renders the Cacotopic Edition "eclipse" icon variants and launch-screen images.
// Usage: swift fork-docs/artwork/render_cacotopic.swift <outdir>, then copy the PNGs into clients/ios/Fork/ForkAssets.xcassets. Needs Century Gothic installed.
let out = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    return ctx.makeImage()!
}

/// App icons must be opaque: flatten onto RGB without alpha.
func opaque(_ image: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func save(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func radial(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

let background: UInt32 = 0x0B0D12
let amber: UInt32 = 0xFFB23F
let ember: UInt32 = 0xFF7A3D

/// Eclipse mark: dark moon over an amber disc, with a corona and a "diamond ring" bead at upper right.
/// `size` is the mark's full width (the corona reaches the edge). `mono` draws it in greys for the tinted icon.
func eclipse(_ ctx: CGContext, center c: CGPoint, size: CGFloat, moon: UInt32, mono: Bool = false) {
    let s = size / 800
    let hot = mono ? 0xFFFFFF : amber
    let warm = mono ? 0xBBBBBB : ember
    let horizonY = c.y + 300 * s
    ctx.saveGState()
    ctx.clip(to: CGRect(x: c.x - 600 * s, y: c.y - 600 * s, width: 1200 * s, height: horizonY - (c.y - 600 * s)))
    radial(ctx, [color(hot, 0.55), color(warm, 0.22), color(warm, 0)], [0, 0.62, 1], center: c, radius: 400 * s)
    ctx.restoreGState()
    // Horizon lines from concept A.
    ctx.setLineCap(.round)
    ctx.setLineWidth(24 * s)
    ctx.setStrokeColor(color(hot))
    ctx.move(to: CGPoint(x: c.x - 330 * s, y: horizonY)); ctx.addLine(to: CGPoint(x: c.x + 330 * s, y: horizonY))
    ctx.strokePath()
    ctx.setStrokeColor(color(hot, 0.45))
    ctx.move(to: CGPoint(x: c.x - 200 * s, y: horizonY + 62 * s)); ctx.addLine(to: CGPoint(x: c.x + 200 * s, y: horizonY + 62 * s))
    ctx.strokePath()
    ctx.setFillColor(color(hot))
    ctx.addEllipse(in: CGRect(x: c.x - 255 * s, y: c.y - 255 * s, width: 510 * s, height: 510 * s))
    ctx.fillPath()
    ctx.setFillColor(color(moon))
    ctx.addEllipse(in: CGRect(x: c.x - 240 * s, y: c.y - 252 * s, width: 490 * s, height: 490 * s))
    ctx.fillPath()
    // Diamond-ring bead where the ring is thickest.
    let angle = -CGFloat.pi / 4
    let bead = CGPoint(x: c.x + cos(angle) * 252 * s, y: c.y + sin(angle) * 252 * s)
    radial(ctx, [color(0xFFFFFF, 0.95), color(hot, 0.6), color(hot, 0)], [0, 0.25, 1], center: bead, radius: 70 * s)
}

// App icon variants, 1024 px.
save(opaque(canvas(1024, 1024) { ctx in
    ctx.setFillColor(color(background)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    radial(ctx, [color(0x1A2030), color(background)], [0, 1], center: CGPoint(x: 512, y: 512), radius: 720)
    eclipse(ctx, center: CGPoint(x: 512, y: 470), size: 800, moon: background)
}), "ForkAppIcon")
save(opaque(canvas(1024, 1024) { ctx in
    ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    eclipse(ctx, center: CGPoint(x: 512, y: 470), size: 800, moon: 0x000000)
}), "ForkAppIconDark")
save(opaque(canvas(1024, 1024) { ctx in
    ctx.setFillColor(color(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    eclipse(ctx, center: CGPoint(x: 512, y: 470), size: 800, moon: 0x000000, mono: true)
}), "ForkAppIconTinted")

// Launch mark on transparent background: 200 pt.
for scale in [2, 3] {
    let px = 200 * scale
    save(canvas(px, px * 6 / 5) { ctx in
        eclipse(ctx, center: CGPoint(x: px / 2, y: px / 2), size: CGFloat(px), moon: background)
    }, "ForkLaunchMark@\(scale)x")
}

// Launch title: "NewsBlur Reader" over "Cacotopic Edition", both Century Gothic.
for scale in [2, 3] {
    let s = CGFloat(scale)
    func line(_ text: String, _ font: String, _ size: CGFloat, _ hex: UInt32, _ kern: CGFloat) -> (CTLine, CGFloat, CGFloat, CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size * s, nil),
            .init(kCTForegroundColorAttributeName as String): color(hex), .kern: kern * s]
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var a: CGFloat = 0, d: CGFloat = 0
        let w = CTLineGetTypographicBounds(l, &a, &d, nil)
        return (l, CGFloat(w), a, d)
    }
    let top = line("NewsBlur Reader", "CenturyGothicPaneuropean", 24, 0xE8EBF0, 0.5)
    let bottom = line("Cacotopic Edition", "CenturyGothicPaneuropean-Light", 15, 0x9AA3B2, 2)
    let gap = 8 * s
    let w = Int(ceil(max(top.1, bottom.1))) + 4
    let h = Int(ceil(top.2 + top.3 + gap + bottom.2 + bottom.3)) + 4
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.textPosition = CGPoint(x: (CGFloat(w) - bottom.1) / 2, y: bottom.3 + 2)
    CTLineDraw(bottom.0, ctx)
    ctx.textPosition = CGPoint(x: (CGFloat(w) - top.1) / 2, y: bottom.3 + bottom.2 + gap + top.3 + 2)
    CTLineDraw(top.0, ctx)
    save(ctx.makeImage()!, "ForkLaunchTitle@\(scale)x")
    if scale == 2 { print("title pt size: \(Double(w) / 2) x \(Double(h) / 2)") }
}

// Preview: icon at home-screen size, and the launch screen at iPad 11" landscape 2x.
let mark = NSImage(contentsOfFile: "\(out)/ForkLaunchMark@2x.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let title = NSImage(contentsOfFile: "\(out)/ForkLaunchTitle@2x.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
save(canvas(2388, 1668) { ctx in
    ctx.setFillColor(color(background)); ctx.fill(CGRect(x: 0, y: 0, width: 2388, height: 1668))
    func draw(_ image: CGImage, centerX: CGFloat, top: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: centerX - CGFloat(image.width) / 2, y: top + CGFloat(image.height)); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.restoreGState()
    }
    draw(mark, centerX: 1194, top: 526)
    draw(title, centerX: 1194, top: 526 + 480 + 40)
}, "preview_launch")
print("ok")
