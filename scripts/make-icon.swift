// Draws the MacSave app icon. Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
}

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)
    // Flip so y grows downward like a screen.
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Squircle background (Big Sur grid: 824pt body, 100pt margin).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    hex(0xAE2A3A).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: hex(0xC8404F), ending: hex(0x8E1E2C))!.draw(in: shape, angle: 90)

    // Three stacked windows, back to front.
    func window(_ r: NSRect, fill: NSColor, bar: NSColor, rows: [(UInt32, CGFloat)]) {
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = .black.withAlphaComponent(0.28)
        sh.shadowBlurRadius = 18
        sh.shadowOffset = NSSize(width: 0, height: -8)
        sh.set()
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34).fill()
        NSGraphicsContext.restoreGraphicsState()
        let barRect = NSRect(x: r.minX, y: r.minY, width: r.width, height: 62)
        let path = NSBezierPath(roundedRect: barRect, xRadius: 34, yRadius: 34)
        path.append(NSBezierPath(rect: NSRect(x: r.minX, y: r.minY + 30, width: r.width, height: 32)))
        bar.setFill()
        path.fill()
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            hex(UInt32(c)).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + 30 + CGFloat(i) * 36, y: r.minY + 19, width: 24, height: 24)).fill()
        }
        for (i, row) in rows.enumerated() {
            let y = r.minY + 100 + CGFloat(i) * 62
            if y + 26 > r.maxY - 20 { break }
            hex(row.0).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.minX + 36, y: y, width: 26, height: 26)).fill()
            hex(0x3B3B3B, 0.28).setFill()
            NSBezierPath(roundedRect: NSRect(x: r.minX + 80, y: y + 3, width: (r.width - 120) * row.1, height: 20),
                         xRadius: 10, yRadius: 10).fill()
        }
    }
    window(NSRect(x: 190, y: 190, width: 520, height: 380), fill: hex(0xCFE4FF), bar: hex(0xB4D2F7), rows: [])
    window(NSRect(x: 250, y: 280, width: 540, height: 400), fill: hex(0xF3F8C8), bar: hex(0xE2EAA6), rows: [])
    window(NSRect(x: 310, y: 380, width: 560, height: 440), fill: .white, bar: hex(0xECECEC),
           rows: [(0x5F2AFF, 0.85), (0x4C6EF5, 0.6), (0x2F9E44, 0.75), (0xF08C00, 0.5), (0xAE2A3A, 0.68)])

    // "Save" badge: down arrow into a tray.
    let badge = NSRect(x: 640, y: 620, width: 230, height: 230)
    NSGraphicsContext.saveGraphicsState()
    let bs = NSShadow()
    bs.shadowColor = .black.withAlphaComponent(0.35)
    bs.shadowBlurRadius = 16
    bs.shadowOffset = NSSize(width: 0, height: -6)
    bs.set()
    hex(0x222222).setFill()
    NSBezierPath(ovalIn: badge).fill()
    NSGraphicsContext.restoreGraphicsState()
    let arrow = NSBezierPath()
    arrow.lineWidth = 22
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 755, y: 668)); arrow.line(to: NSPoint(x: 755, y: 770))
    arrow.move(to: NSPoint(x: 712, y: 728)); arrow.line(to: NSPoint(x: 755, y: 772)); arrow.line(to: NSPoint(x: 798, y: 728))
    arrow.move(to: NSPoint(x: 700, y: 800)); arrow.line(to: NSPoint(x: 810, y: 800))
    NSColor.white.setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MacSave-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try draw(pt * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try p.run()
p.waitUntilExit()
if CommandLine.arguments.count > 2 {
    try draw(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("Wrote \(out)")
