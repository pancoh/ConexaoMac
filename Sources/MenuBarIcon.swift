import AppKit

enum MenuBarIcon {
    static let connected = makePulse(disconnected: false)
    static let disconnected = makePulse(disconnected: true)
    static let paused = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Monitoramento pausado")

    private static func makePulse(disconnected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let pulse = NSBezierPath()
            pulse.move(to: NSPoint(x: 1.5, y: 9))
            pulse.line(to: NSPoint(x: 5.3, y: 9))
            pulse.line(to: NSPoint(x: 7.4, y: 13))
            pulse.line(to: NSPoint(x: 10.3, y: 4.5))
            pulse.line(to: NSPoint(x: 12.8, y: 9))
            pulse.line(to: NSPoint(x: 18.5, y: 9))
            pulse.lineWidth = 1.5
            pulse.lineCapStyle = .round
            pulse.lineJoinStyle = .round
            pulse.stroke()
            for x in [CGFloat(1.5), CGFloat(18.5)] {
                NSBezierPath(ovalIn: NSRect(x: x - 1, y: 8, width: 2, height: 2)).fill()
            }
            if disconnected {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 4, y: 15))
                slash.line(to: NSPoint(x: 16, y: 3))
                // A borda transparente separa a indicação de falha do pulso.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .clear
                slash.lineWidth = 3.5
                slash.lineCapStyle = .round
                slash.stroke()
                NSGraphicsContext.restoreGraphicsState()
                slash.lineWidth = 1.5
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
