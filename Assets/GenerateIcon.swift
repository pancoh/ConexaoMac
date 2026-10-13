import AppKit

// Símbolo de conexão com pulso, desenhado como vetor em todas as resoluções.
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)]
for (name, size) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.25, blue: 0.34, alpha: 1), ending: NSColor(srgbRed: 0.025, green: 0.12, blue: 0.21, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor(srgbRed: 0.19, green: 0.43, blue: 0.50, alpha: 0.5).setStroke()
    tile.lineWidth = 3; tile.stroke()
    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: 235, y: 500))
    pulse.line(to: NSPoint(x: 361, y: 500))
    pulse.line(to: NSPoint(x: 430, y: 635))
    pulse.line(to: NSPoint(x: 526, y: 354))
    pulse.line(to: NSPoint(x: 608, y: 500))
    pulse.line(to: NSPoint(x: 789, y: 500))
    pulse.lineWidth = 48
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSColor(srgbRed: 0.93, green: 0.98, blue: 1, alpha: 1).setStroke()
    pulse.stroke()
    NSColor(srgbRed: 0.24, green: 0.86, blue: 0.73, alpha: 1).setFill()
    for x in [CGFloat(235), CGFloat(789)] {
        NSBezierPath(ovalIn: NSRect(x: x - 43, y: 457, width: 86, height: 86)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
}
