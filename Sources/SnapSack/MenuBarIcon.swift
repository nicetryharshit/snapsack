import AppKit

/// The menu bar glyph: a cursor arrow carrying a little picture card, drawn in code as a template image
/// so it follows light/dark menu bars automatically.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // The card (a screenshot).
            let card = NSBezierPath(
                roundedRect: NSRect(x: 6.3, y: 4.8, width: 10.4, height: 9.8),
                xRadius: 2.1,
                yRadius: 2.1
            )
            card.lineWidth = 1.5
            NSColor.black.setStroke()
            card.stroke()

            // A hint of picture: a little peak and a sun.
            let peak = NSBezierPath()
            peak.move(to: NSPoint(x: 9.6, y: 13.0))
            peak.line(to: NSPoint(x: 12.0, y: 9.9))
            peak.line(to: NSPoint(x: 13.4, y: 11.5))
            peak.line(to: NSPoint(x: 14.4, y: 10.5))
            peak.line(to: NSPoint(x: 15.6, y: 13.0))
            peak.lineWidth = 1.1
            peak.lineJoinStyle = .round
            peak.lineCapStyle = .round
            peak.stroke()

            // The cursor, with a gap carved out of the card around it.
            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 2.4, y: 1.4))
            cursor.line(to: NSPoint(x: 2.4, y: 13.6))
            cursor.line(to: NSPoint(x: 5.3, y: 10.8))
            cursor.line(to: NSPoint(x: 7.2, y: 15.4))
            cursor.line(to: NSPoint(x: 9.2, y: 14.5))
            cursor.line(to: NSPoint(x: 7.3, y: 10.0))
            cursor.line(to: NSPoint(x: 11.2, y: 10.0))
            cursor.close()

            let context = NSGraphicsContext.current
            context?.compositingOperation = .clear
            cursor.lineWidth = 3.4
            cursor.lineJoinStyle = .round
            cursor.stroke()
            context?.compositingOperation = .sourceOver

            NSColor.black.setFill()
            cursor.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
