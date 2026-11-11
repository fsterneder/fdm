import AppKit

// Shared by the app's Dock icon and the build-time Finder icon generator.
struct InstrumentIconColors {
    let background: NSColor
    let neutral: NSColor
    let tempo: NSColor
    let playingBeat: NSColor
    let action: NSColor
    let actionForeground: NSColor
    let lcdBackground: NSColor
    let lcdInk: NSColor

    static let defaultTheme = InstrumentIconColors(
        background: rgb(0x151818), neutral: rgb(0xE2E5DE),
        tempo: rgb(0xFF7D40), playingBeat: rgb(0x172019),
        action: rgb(0xFF7D40), actionForeground: rgb(0x101614),
        lcdBackground: rgb(0xA9B69E), lcdInk: rgb(0x172019)
    )
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum InstrumentIconArtwork {
    static func make(colors: InstrumentIconColors) -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { bounds in
            let sx = bounds.width / 1024
            let sy = bounds.height / 1024
            let unit = min(sx, sy)
            // Artwork coordinates use a top-left origin, independent of backing scale.
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: bounds.minX + x * sx, y: bounds.minY + (1024 - y) * sy)
            }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
                NSRect(x: bounds.minX + x * sx, y: bounds.minY + (1024 - y - h) * sy,
                       width: w * sx, height: h * sy)
            }
            func blend(_ fraction: CGFloat) -> NSColor {
                colors.background.blended(withFraction: fraction, of: colors.neutral) ?? colors.background
            }
            func fill(_ path: NSBezierPath, _ color: NSColor) {
                color.setFill()
                path.fill()
            }
            func stroke(_ path: NSBezierPath, _ color: NSColor, _ width: CGFloat) {
                color.setStroke()
                path.lineWidth = width * unit
                path.stroke()
            }
            func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
                if let gradient = NSGradient(starting: top, ending: bottom) {
                    gradient.draw(in: path, angle: -90)
                } else {
                    fill(path, bottom)
                }
            }
            func polygon(_ points: [NSPoint]) -> NSBezierPath {
                let path = NSBezierPath()
                guard let first = points.first else { return path }
                path.move(to: first)
                for p in points.dropFirst() { path.line(to: p) }
                path.close()
                return path
            }
            let housing = NSBezierPath(roundedRect: rect(42, 50, 940, 924),
                                        xRadius: 165 * sx, yRadius: 165 * sy)
            gradient(housing, blend(0.035), colors.background)
            stroke(housing, blend(0.10), 3)

            let screen = NSBezierPath(roundedRect: rect(102, 140, 820, 300),
                                       xRadius: 38 * sx, yRadius: 38 * sy)
            gradient(screen, colors.lcdBackground,
                     colors.lcdBackground.blended(withFraction: 0.04, of: colors.background) ?? colors.lcdBackground)
            stroke(screen, blend(0.35), 7)
            // Fixed, readable icon motif: two played beats and one empty beat.
            for index in 0..<3 {
                let x = CGFloat(286 + index * 185)
                let triangle = polygon([point(x, 230), point(x + 100, 290), point(x, 350)])
                if index < 2 { fill(triangle, colors.playingBeat) }
                stroke(triangle, index < 2 ? colors.playingBeat : colors.lcdInk, 6)
            }

            // Plain tempo wheel: no tick marks, scales, or decorative rings.
            let wheel = NSBezierPath(ovalIn: rect(142, 510, 360, 360))
            gradient(wheel, blend(0.21), blend(0.12))
            stroke(wheel, blend(0.30), 2)
            let pointer = NSBezierPath()
            pointer.move(to: point(170, 685))
            pointer.line(to: point(215, 689))
            pointer.lineCapStyle = .round
            stroke(pointer, colors.tempo, 14)

            let centers: [(CGFloat, CGFloat)] = [(650, 600), (830, 600), (650, 785), (830, 785)]
            for (index, center) in centers.enumerated() {
                let (cx, cy) = center
                let button = NSBezierPath(ovalIn: rect(cx - 76, cy - 76, 152, 152))
                if index == 3 {
                    fill(button, colors.action)
                    stroke(button, colors.action, 2)
                } else {
                    gradient(button, blend(0.19), blend(0.10))
                    stroke(button, blend(0.26), 2)
                }
                switch index {
                case 0:
                    fill(polygon([point(cx, cy - 25), point(cx + 26, cy + 20),
                                  point(cx - 26, cy + 20)]), colors.neutral)
                case 1:
                    let speaker = polygon([point(cx - 29, cy - 11), point(cx - 15, cy - 11),
                                           point(cx + 2, cy - 25), point(cx + 2, cy + 25),
                                           point(cx - 15, cy + 11), point(cx - 29, cy + 11)])
                    speaker.lineJoinStyle = .round
                    stroke(speaker, colors.neutral, 6)
                    for offset in [CGFloat(14), CGFloat(28)] {
                        let wave = NSBezierPath()
                        wave.move(to: point(cx + offset, cy - 21))
                        wave.curve(to: point(cx + offset, cy + 21),
                                   controlPoint1: point(cx + offset + 15, cy - 10),
                                   controlPoint2: point(cx + offset + 15, cy + 10))
                        wave.lineCapStyle = .round
                        stroke(wave, colors.neutral, 5)
                    }
                case 2:
                    fill(polygon([point(cx - 26, cy - 20), point(cx + 26, cy - 20),
                                  point(cx, cy + 25)]), colors.neutral)
                default:
                    fill(NSBezierPath(rect: rect(cx - 21, cy - 21, 42, 42)), colors.actionForeground)
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
