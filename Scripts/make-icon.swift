// Draws the app icon at every size macOS wants and writes an .iconset.
// Run with: make icon   (iconutil, which ships with macOS, turns it into an .icns)
import AppKit
import CoreGraphics
import Foundation

let iconSizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: Int) -> Data? {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        // Dark rounded square, like a menu-bar app at rest.
        let corner = side * 0.22
        let background = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.13, alpha: 1),
        ])?.draw(in: background, angle: -90)

        // The draining ring, three-quarters full, in the app's amber.
        let inset = side * 0.22
        let ringRect = rect.insetBy(dx: inset, dy: inset)
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let radius = ringRect.width / 2
        let lineWidth = max(1, side * 0.085)

        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius, startAngle: 90, endAngle: 90 - 270, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 1.0, green: 0.63, blue: 0.29, alpha: 1).setStroke()
        arc.stroke()

        // The pupil: this is EyesUp, after all.
        let pupil = NSBezierPath(ovalIn: NSRect(x: centre.x - side * 0.055, y: centre.y - side * 0.055,
                                                width: side * 0.11, height: side * 0.11))
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.5, alpha: 1).setFill()
        pupil.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    bitmap.size = NSSize(width: side, height: side)
    return bitmap.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in iconSizes {
    guard let data = drawIcon(size: size) else { continue }
    try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    if size <= 512, let retina = drawIcon(size: size * 2) {
        try retina.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
print("wrote \(iconset.path)")
