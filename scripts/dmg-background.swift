// Renders the DMG window background (660x400 @1x and @2x) into Design/.
// Usage: swift scripts/dmg-background.swift   (run from repo root)
import AppKit

let fontsDir = URL(fileURLWithPath: "Resources/Fonts")
for f in (try? FileManager.default.contentsOfDirectory(at: fontsDir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "ttf" {
    CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
}
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 255)/255, green: CGFloat(v >> 8 & 255)/255, blue: CGFloat(v & 255)/255, alpha: a)
}

func render(scale: CGFloat, to path: String) {
    let W: CGFloat = 660, H: CGFloat = 400
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Warm mid-tone "desk": Finder's black (light mode) and white (dark mode) labels both stay readable.
    NSGradient(starting: hex(0x9A876B), ending: hex(0x86745A))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // faint ruled lines, like the icon's paper
    hex(0xFFF6E3, 0.07).setStroke()
    for y in stride(from: 40.0, to: H, by: 34) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: 0, y: y)); p.line(to: NSPoint(x: W, y: y)); p.lineWidth = 1; p.stroke()
    }

    func text(_ s: String, _ font: String, _ size: CGFloat, _ color: NSColor, centerX: CGFloat, top: CGFloat) {
        let f = NSFont(name: font, size: size) ?? .systemFont(ofSize: size)
        let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
        let w = str.size().width
        str.draw(at: NSPoint(x: centerX - w / 2, y: H - top - f.ascender))
    }
    text("longhand", "iAWriterQuattroS-Bold", 30, hex(0xFFF6E3), centerX: W / 2, top: 34)
    text("Drag longhand into Applications to install", "iAWriterQuattroS-Regular", 14, hex(0xFFF6E3, 0.85), centerX: W / 2, top: 80)

    // Hand-drawn ink arrow between the icons (icons sit at x=180 and x=480, y=215 from top).
    let y = H - 205
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: y - 4))
    arrow.curve(to: NSPoint(x: 396, y: y + 2), controlPoint1: NSPoint(x: 300, y: y + 26), controlPoint2: NSPoint(x: 352, y: y + 24))
    arrow.lineWidth = 5; arrow.lineCapStyle = .round
    hex(0xFFF6E3).setStroke(); arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: y + 16)); head.line(to: NSPoint(x: 398, y: y + 1)); head.line(to: NSPoint(x: 376, y: y - 7))
    head.lineWidth = 5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.stroke()

    text("A quiet Markdown editor for writing books", "iAWriterQuattroS-Italic", 12, hex(0xFFF6E3, 0.7), centerX: W / 2, top: 318)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: "Design/dmg-background.png")
render(scale: 2, to: "Design/dmg-background@2x.png")
print("ok")
