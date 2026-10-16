import AppKit

/// An original, monochrome purifier silhouette, rendered as a native template
/// so macOS keeps it legible against both light and dark menu bars.
@MainActor
enum PurifierStatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 13, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            let loop = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 6.2, width: 8.2, height: 11), xRadius: 3.5, yRadius: 3.5)
            loop.lineWidth = 1.3
            loop.stroke()

            let neck = NSBezierPath()
            neck.move(to: NSPoint(x: 6.35, y: 6))
            neck.line(to: NSPoint(x: 6.35, y: 5))
            neck.lineWidth = 1.3
            neck.stroke()

            let base = NSBezierPath(roundedRect: NSRect(x: 2.4, y: 0.8, width: 7.9, height: 4.4), xRadius: 1.2, yRadius: 1.2)
            base.lineWidth = 1.1
            base.stroke()

            for y in [2.3, 3.7] {
                let vent = NSBezierPath()
                vent.move(to: NSPoint(x: 4, y: y))
                vent.line(to: NSPoint(x: 8.7, y: y))
                vent.lineWidth = 0.65
                vent.stroke()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Air purifier"
        return image
    }()
}
