import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 218, yRadius: 218)
        NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.33, alpha: 1).setFill(); background.fill()
        NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.87, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 226, y: 204, width: 572, height: 616), xRadius: 78, yRadius: 78).fill()
        NSColor(calibratedRed: 0.76, green: 0.81, blue: 0.67, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 328, y: 746, width: 368, height: 108), xRadius: 40, yRadius: 40).fill()
        let check = NSBezierPath(); check.move(to: NSPoint(x: 355, y: 480)); check.line(to: NSPoint(x: 469, y: 366)); check.line(to: NSPoint(x: 682, y: 607)); check.lineWidth = 61; check.lineCapStyle = .round; check.lineJoinStyle = .round
        NSColor(calibratedRed: 0.20, green: 0.40, blue: 0.33, alpha: 1).setStroke(); check.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
