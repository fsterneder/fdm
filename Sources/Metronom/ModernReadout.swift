import SwiftUI
import AppKit
import TempoCore

enum DisplayGeometry {
    static let width: CGFloat = 332
    static let mainHeight: CGFloat = 196
    static let widgetDisplayWidth: CGFloat = 200
    static let widgetDisplayHeight = widgetDisplayWidth * mainHeight / width
    static let widgetWidth = widgetDisplayWidth + 56
    static let widgetHeight = widgetDisplayHeight + 20
}

@MainActor
struct ModernReadout: View {
    @ObservedObject var model: Metronome
    @State private var editingTempo = false
    private var palette: InstrumentPalette { model.theme.palette }
    private var subdivisionText: String {
        switch model.subdivisions {
        case 2: return "1/8"
        case 3: return "1/8T"
        case 4: return "1/16"
        default: return "1/4"
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / DisplayGeometry.width,
                            geometry.size.height / DisplayGeometry.mainHeight)
            VStack(spacing: 24 * scale) {
                HStack(spacing: 0) {
                    VStack(spacing: 2 * scale) {
                        tempoValue(scale: scale)
                        caption("BPM", scale: scale)
                    }
                    .frame(width: 166 * scale)
                    VStack(spacing: 2 * scale) {
                        Text(model.inSilentBar ? "GAP" : subdivisionText)
                            .font(.system(size: (model.inSilentBar ? 43 : 48) * scale, weight: .regular))
                            .monospacedDigit()
                            .foregroundColor(model.inSilentBar ? palette.neutral : palette.beat)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .frame(width: 158 * scale, height: 80 * scale)
                        caption(model.inSilentBar ? "SILENT BAR" : "SUBDIVISION", scale: scale)
                    }
                    .frame(width: 166 * scale)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.inSilentBar ? "Silent practice bar" : "Subdivision")
                    .accessibilityValue(model.inSilentBar ? "Gap" : "\(model.subdivisions) clicks per beat")
                }
                .frame(height: 104 * scale)
                BeatLights(model: model, scale: scale)
                    .frame(height: 68 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .onDisappear {
            editingTempo = false
            model.editingTempo = false
        }
    }
    private func caption(_ title: String, scale: CGFloat) -> some View {
        Text(title).font(.system(size: 10 * scale, weight: .medium))
            .tracking(1.4 * scale).foregroundColor(palette.neutral.opacity(0.65))
            .lineLimit(1).frame(height: 18 * scale)
    }
    private func tempoValue(scale: CGFloat) -> some View {
        ZStack {
            Text(String(model.bpm))
                .font(.system(size: 64 * scale, weight: .semibold))
                .monospacedDigit().foregroundColor(palette.tempo)
                .minimumScaleFactor(0.7).lineLimit(1)
                .opacity(editingTempo ? 0 : 1)
            if editingTempo {
                InlineTempoField(bpm: model.bpm, color: palette.tempo, fontSize: 64 * scale,
                    onSet: { value in
                        if model.bpm != value { model.bpm = value }
                        editingTempo = false
                        model.editingTempo = false
                    },
                    onCancel: {
                        editingTempo = false
                        model.editingTempo = false
                    })
                    .frame(width: 158 * scale, height: 80 * scale)
            } else {
                TempoDragArea(bpm: model.bpm,
                    onSet: { value in if model.bpm != value { model.bpm = value } },
                    onClick: { editingTempo = true; model.editingTempo = true },
                    onDragState: { model.editingTempo = $0 })
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 166 * scale, height: 80 * scale)
        .accessibilityElement(children: editingTempo ? .contain : .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(model.bpm) beats per minute")
        .accessibilityHint("Drag up or down to change tempo, or click to type.")
        .accessibilityAdjustableAction { direction in
            model.bpm = Tempo.clamp(model.bpm + (direction == .increment ? 1 : -1))
        }
        .help("Drag up/down to adjust BPM. Click to type.")
    }
}

@MainActor
private struct BeatLights: View {
    @ObservedObject var model: Metronome
    let scale: CGFloat
    var body: some View {
        let count = max(1, model.beats)
        let noAccent = model.beats == 0
        let playing = model.playing
        let current = model.currentBeat
        let beatTime = model.beatTime
        let bpm = model.bpm
        let palette = model.theme.palette
        let gap: CGFloat = count > 4 ? 10 : 20
        let diameter = min(CGFloat(68), (DisplayGeometry.width - CGFloat(count - 1) * gap) / CGFloat(count))
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !noAccent || !playing)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - beatTime)
            let pulse = playing && current >= 0 && elapsed < min(0.14, (60 / Double(bpm)) * 0.45)
            HStack(spacing: gap * scale) {
                ForEach(0..<count, id: \.self) { index in
                    let isCurrent = noAccent ? pulse : playing && current == index
                    let isPlayed = !noAccent && playing && current >= 0 && index < current
                    let color = isCurrent ? palette.playingBeat : palette.neutral
                    Circle()
                        .fill(isCurrent || isPlayed ? color : Color.clear)
                        .overlay(Circle().strokeBorder(color, lineWidth: 2.5 * scale))
                        .frame(width: diameter * scale, height: diameter * scale)
                        .accessibilityLabel(noAccent ? "Unaccented beat" : "Beat \(index + 1) of \(count)")
                        .accessibilityValue(isCurrent ? "Current" : (isPlayed ? "Played" : "Upcoming"))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

@MainActor
private struct TempoDragArea: NSViewRepresentable {
    let bpm: Int
    let onSet: (Int) -> Void
    let onClick: () -> Void
    let onDragState: (Bool) -> Void
    func makeNSView(context: Context) -> TempoDragView {
        let view = TempoDragView()
        configure(view)
        return view
    }
    func updateNSView(_ view: TempoDragView, context: Context) { configure(view) }
    private func configure(_ view: TempoDragView) {
        view.bpm = bpm
        view.onSet = onSet
        view.onClick = onClick
        view.onDragState = onDragState
    }
    static func dismantleNSView(_ view: TempoDragView, coordinator: ()) { view.cancelInteraction() }
}

@MainActor
private final class TempoDragView: NSView {
    var bpm = 120
    var onSet: ((Int) -> Void)?
    var onClick: (() -> Void)?
    var onDragState: ((Bool) -> Void)?
    private var scrubber: TempoScrubber?
    private var pressX: CGFloat = 0
    private var pressY: CGFloat = 0
    private var lastY: CGFloat = 0
    private var dragging = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) {
        pressX = event.locationInWindow.x
        pressY = event.locationInWindow.y
        lastY = pressY
        dragging = false
        scrubber = TempoScrubber(bpm: bpm)
    }
    override func mouseDragged(with event: NSEvent) {
        guard var state = scrubber else { return }
        let y = event.locationInWindow.y
        if !dragging {
            guard max(abs(y - pressY), abs(event.locationInWindow.x - pressX)) >= 3 else { return }
            dragging = true
            onDragState?(true)
        }
        let value = state.move(upwardPoints: Double(y - lastY))
        scrubber = state
        lastY = y
        if value != bpm { onSet?(value) }
    }
    override func mouseUp(with event: NSEvent) {
        guard scrubber != nil else { return }
        let wasDragging = dragging
        cancelInteraction()
        if !wasDragging { onClick?() }
    }
    func cancelInteraction() {
        if dragging { onDragState?(false) }
        scrubber = nil
        dragging = false
    }
}
