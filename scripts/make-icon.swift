#!/usr/bin/swift
import AppKit

// Use sips for pixel resizing; avoid AppKit bitmap point/backing-scale conversions.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift scripts/make-icon.swift SOURCE.png OUTPUT.icns")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let destination = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let fm = FileManager.default
let sourceData = try Data(contentsOf: source)
guard let sourceBitmap = NSBitmapImageRep(data: sourceData),
      sourceBitmap.pixelsWide == sourceBitmap.pixelsHigh,
      sourceBitmap.pixelsWide >= 1024 else {
    fatalError("Icon source must be a square PNG of at least 1024 pixels.")
}
try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconset = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
let packagedURL = iconset.deletingPathExtension().appendingPathExtension("icns")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer {
    try? fm.removeItem(at: iconset)
    try? fm.removeItem(at: packagedURL)
}
func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "fdm-3.Icon", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(executable) failed."])
    }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 2 ? "@2x" : ""
        let file = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try run("/usr/bin/sips", ["-z", String(pixels), String(pixels),
                                  "-s", "dpiWidth", "72", "-s", "dpiHeight", "72",
                                  source.path, "--out", file.path])
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: file)),
              bitmap.pixelsWide == pixels, bitmap.pixelsHigh == pixels else {
            fatalError("Incorrect icon dimensions at \(pixels) pixels.")
        }
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", packagedURL.path])
guard let packaged = NSImage(contentsOf: packagedURL), packaged.isValid else {
    fatalError("Generated icon could not be decoded.")
}
try Data(contentsOf: packagedURL).write(to: destination, options: .atomic)
print("Generated \(destination.lastPathComponent)")
