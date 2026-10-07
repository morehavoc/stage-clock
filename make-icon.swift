// Renders the Stage Clock app icon into an .iconset folder; build.sh turns it into AppIcon.icns.
// Usage: swiftc -O make-icon.swift -o /tmp/mkicon && /tmp/mkicon AppIcon.iconset && iconutil -c icns AppIcon.iconset
import Cocoa

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let red = CGColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)   // #FF3B30, the clock's default

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    // macOS icon grid: 824 pt body inset 100 pt, with a soft drop shadow.
    let shape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1),
                                                   CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    // Countdown ring: faint track, red remaining arc from 12 o'clock clockwise (three quarters left).
    let c = CGPoint(x: 512, y: 512), r: CGFloat = 292
    ctx.setLineWidth(58); ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
    ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
    ctx.setStrokeColor(red)
    ctx.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: -.pi, clockwise: true); ctx.strokePath()
    // "30" set optically centred on its figure height.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let font = NSFont.monospacedDigitSystemFont(ofSize: 250, weight: .bold)
    let str = NSAttributedString(string: "30", attributes: [.font: font, .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(str)
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: (512 - ink.midX).rounded(), y: (512 - ink.midY).rounded())
    CTLineDraw(line, ctx)
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("wrote \(outDir)")
