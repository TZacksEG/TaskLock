import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("TaskLock.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let dimension = CGFloat(pixels)
        NSColor(calibratedRed: 0.04, green: 0.065, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: dimension * 0.05, y: dimension * 0.05, width: dimension * 0.9, height: dimension * 0.9), xRadius: dimension * 0.21, yRadius: dimension * 0.21).fill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: dimension * 0.5, y: dimension * 0.79))
        path.line(to: NSPoint(x: dimension * 0.76, y: dimension * 0.68))
        path.line(to: NSPoint(x: dimension * 0.72, y: dimension * 0.40))
        path.curve(to: NSPoint(x: dimension * 0.5, y: dimension * 0.21), controlPoint1: NSPoint(x: dimension * 0.69, y: dimension * 0.31), controlPoint2: NSPoint(x: dimension * 0.56, y: dimension * 0.24))
        path.curve(to: NSPoint(x: dimension * 0.28, y: dimension * 0.40), controlPoint1: NSPoint(x: dimension * 0.44, y: dimension * 0.24), controlPoint2: NSPoint(x: dimension * 0.31, y: dimension * 0.31))
        path.line(to: NSPoint(x: dimension * 0.24, y: dimension * 0.68)); path.close()
        NSColor(calibratedRed: 0.58, green: 0.91, blue: 0.77, alpha: 1).setStroke()
        path.lineWidth = dimension * 0.045; path.lineJoinStyle = .round; path.stroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: dimension * 0.37, y: dimension * 0.51))
        check.line(to: NSPoint(x: dimension * 0.47, y: dimension * 0.42))
        check.line(to: NSPoint(x: dimension * 0.65, y: dimension * 0.61))
        check.lineWidth = dimension * 0.055; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
