import AppKit

/// Menu-bar glyph. The arc drains as the session runs down; a full ring means no end time; a faint ring means the Mac may sleep.
enum RingIcon {
    static func image(active: Bool, fraction: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = rect.insetBy(dx: 2.5, dy: 2.5)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = 1.6
            NSColor.black.withAlphaComponent(active ? 0.3 : 0.45).setStroke()
            track.stroke()
            guard active else { return true }

            let filled = max(0.02, min(1, fraction ?? 1))
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: circle.width / 2,
                startAngle: 90, endAngle: 90 - 360 * filled, clockwise: true
            )
            arc.lineWidth = 2.4
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = active ? "EyesUpGuardian: keeping your Mac awake" : "EyesUpGuardian: your Mac may sleep"
        return image
    }
}
