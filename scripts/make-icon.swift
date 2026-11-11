#!/usr/bin/swift
import AppKit

// Render vector artwork at each native icon resolution; no image dependencies.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/make-icon.swift OUTPUT.icns")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let fm = FileManager.default
try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconset = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

func render(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "fdm-3.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    func rounded(_ rect: CGRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    rounded(CGRect(x: 64, y: 64, width: 896, height: 896), radius: 200,
            color: NSColor(calibratedWhite: 0.16, alpha: 1))
    rounded(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 170,
            color: NSColor(calibratedWhite: 0.095, alpha: 1))
    rounded(CGRect(x: 190, y: 584, width: 644, height: 244), radius: 40,
            color: NSColor(calibratedRed: 0.70, green: 0.77, blue: 0.61, alpha: 1))
    // Three crisp beat marks stay readable at small Dock sizes.
    for (x, height) in [(286.0, 92.0), (458.0, 140.0), (630.0, 92.0)] {
        rounded(CGRect(x: x, y: 632, width: 108, height: height), radius: 10,
                color: NSColor(calibratedWhite: 0.12, alpha: 1))
    }
    rounded(CGRect(x: 352, y: 184, width: 320, height: 320), radius: 160,
            color: NSColor(calibratedWhite: 0.29, alpha: 1))
    rounded(CGRect(x: 372, y: 204, width: 280, height: 280), radius: 140,
            color: NSColor(calibratedWhite: 0.18, alpha: 1))
    let pointer = NSBezierPath()
    pointer.move(to: NSPoint(x: 512, y: 344))
    pointer.line(to: NSPoint(x: 570, y: 438))
    pointer.lineWidth = 24
    pointer.lineCapStyle = .round
    NSColor(calibratedRed: 1, green: 0.48, blue: 0.12, alpha: 1).setStroke()
    pointer.stroke()
    context.flush()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "fdm-3.Icon", code: 2)
    }
    return png
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try render(pixels: size * scale).write(to: file)
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "fdm-3.Icon", code: Int(process.terminationStatus))
}
print("Generated \(destination.lastPathComponent)")
