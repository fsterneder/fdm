import AppKit

struct InstrumentIconColors {
    let background: NSColor
    let neutral: NSColor
    let accent: NSColor?
    let playingBeat: NSColor

    static let defaultTheme = InstrumentIconColors(
        background: rgb(0x17191B), neutral: rgb(0xF8F6F0), accent: nil, playingBeat: rgb(0xFF7D40)
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
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
                NSRect(x: bounds.minX + x * sx, y: bounds.minY + y * sy,
                       width: width * sx, height: height * sy)
            }
            // Standard 824-pixel tile on a 1024-pixel canvas: 100 pixels clear on all sides.
            // No shadow, outline, or glow extends the visible tile beyond these bounds.
            let tile = NSBezierPath(roundedRect: rect(100, 100, 824, 824),
                                    xRadius: 185 * sx, yRadius: 185 * sy)
            colors.background.setFill()
            tile.fill()

            let centers: [CGFloat] = [254, 426, 598, 770]
            for (index, center) in centers.enumerated() {
                let circleRect = rect(center - 72, 440, 144, 144)
                if index < 3 {
                    // Completed accent, completed neutral, current beat, upcoming beat.
                    let fill = index == 2 ? colors.playingBeat : (index == 0 ? (colors.accent ?? colors.neutral) : colors.neutral)
                    fill.setFill()
                    NSBezierPath(ovalIn: circleRect).fill()
                } else {
                    // Inset the stroke so hollow and filled circles have identical outer sizes.
                    let circle = NSBezierPath(ovalIn: circleRect.insetBy(dx: 9 * sx, dy: 9 * sy))
                    circle.lineWidth = 18 * min(sx, sy)
                    colors.neutral.setStroke()
                    circle.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
