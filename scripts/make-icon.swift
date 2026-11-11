import AppKit

@main
struct IconBuilder {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Usage: make-icon OUTPUT.icns")
        }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconset = folder.appendingPathComponent("AppIcon.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        // Rasterize the same resolution-independent drawing used by the Dock.
        // sips handles every final pixel size, avoiding bitmap point/backing-scale mismatches.
        let artwork = InstrumentIconArtwork.make(colors: .defaultTheme)
        guard let cgImage = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fatalError("Could not render the default icon.")
        }
        let master = folder.appendingPathComponent("AppIcon.png")
        try png.write(to: master)
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
                                          master.path, "--out", file.path])
                guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: file)),
                      bitmap.pixelsWide == pixels, bitmap.pixelsHigh == pixels else {
                    fatalError("Incorrect icon dimensions at \(pixels) pixels.")
                }
            }
        }
        let packaged = folder.appendingPathComponent("AppIcon.icns")
        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", packaged.path])
        guard let decoded = NSImage(contentsOf: packaged), decoded.isValid else {
            fatalError("Generated icon could not be decoded.")
        }
        try Data(contentsOf: packaged).write(to: destination, options: .atomic)
        try png.write(to: destination.deletingPathExtension().appendingPathExtension("png"), options: .atomic)
        print("Generated \(destination.lastPathComponent)")
    }
}
