#!/usr/bin/swift
import AppKit

// Package the source artwork using Apple's native iconutil.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift scripts/make-icon.swift SOURCE.png OUTPUT.icns")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard let artwork = NSImage(contentsOf: source), artwork.isValid else {
    fatalError("Cannot decode icon artwork: \(source.path)")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
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
    graphics.imageInterpolation = .high
    artwork.draw(in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)),
                 from: .zero, operation: .copy, fraction: 1)
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
let packagedURL = iconset.deletingPathExtension().appendingPathExtension("icns")
defer { try? fm.removeItem(at: packagedURL) }
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", packagedURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "fdm-3.Icon", code: Int(process.terminationStatus))
}
guard let packaged = NSImage(contentsOf: packagedURL), packaged.isValid else {
    throw NSError(domain: "fdm-3.Icon", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "Generated icon could not be decoded."])
}
try Data(contentsOf: packagedURL).write(to: destination, options: .atomic)
print("Generated \(destination.lastPathComponent)")
