import SwiftUI
import AppKit
import TempoCore

enum DisplayGeometry {
    static let width: CGFloat = 332
    static let mainHeight: CGFloat = 196
    static let widgetWidth: CGFloat = 244
    static let widgetHeight: CGFloat = 52
}

@MainActor
struct ModernReadout: View {
    @ObservedObject var model: Metronome
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
                        TempoValue(model: model, fontSize: 64 * scale, width: 166 * scale, height: 80 * scale)
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
                    .overlay {
                        ValueDragArea(value: model.subdivisions, bounds: 1...4, pointsPerStep: 12,
                            onSet: { value in
                                if model.subdivisions != value { model.subdivisions = value }
                            }, onDoubleClick: nil, onDragState: { model.editingTempo = $0 })
                            .frame(width: 166 * scale, height: 104 * scale)
                            .accessibilityHidden(true)
                    }
                    .help("Drag up/down to change subdivision.")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.inSilentBar ? "Silent practice bar" : "Subdivision")
                    .accessibilityValue(model.inSilentBar ? "Gap" : "\(model.subdivisions) clicks per beat")
                }
                .frame(height: 104 * scale)
                BeatLights(model: model, width: DisplayGeometry.width * scale, maxDiameter: 68 * scale, spacing: 20 * scale)
                    .frame(height: 68 * scale)

            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }
    private func caption(_ title: String, scale: CGFloat) -> some View {
        Text(title).font(.system(size: 10 * scale, weight: .medium))
            .tracking(1.4 * scale).foregroundColor(palette.neutral.opacity(0.65))
            .lineLimit(1).frame(height: 18 * scale)
    }
}

@MainActor
struct TempoValue: View {
    @ObservedObject var model: Metronome
    let fontSize: CGFloat
    let width: CGFloat
    let height: CGFloat
    @State private var editingTempo = false
    private var palette: InstrumentPalette { model.theme.palette }
    var body: some View {
        ZStack {
            Text(String(model.bpm))
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit().foregroundColor(palette.tempo)
                .minimumScaleFactor(0.7).lineLimit(1)
                .opacity(editingTempo ? 0 : 1)
            if editingTempo {
                InlineTempoField(bpm: model.bpm, color: palette.tempo, fontSize: fontSize,
                    onSet: { value in
                        if model.bpm != value { model.bpm = value }
                        editingTempo = false
                        model.editingTempo = false
                    },
                    onCancel: {
                        editingTempo = false
                        model.editingTempo = false
                    })
                    .frame(width: width, height: height)
            } else {
                ValueDragArea(value: model.bpm, bounds: 30...252, pointsPerStep: 3,
                    onSet: { value in if model.bpm != value { model.bpm = value } },
                    onDoubleClick: { editingTempo = true; model.editingTempo = true },
                    onDragState: { model.editingTempo = $0 })
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: editingTempo ? .contain : .ignore)
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(model.bpm) beats per minute")
        .accessibilityHint("Drag up or down to change tempo, or double-click to type.")
        .accessibilityAdjustableAction { direction in
            model.bpm = Tempo.clamp(model.bpm + (direction == .increment ? 1 : -1))
        }
        .help("Drag up/down to adjust BPM. Double-click to type.")
        .onDisappear {
            if editingTempo { model.editingTempo = false }
            editingTempo = false
        }
    }
}

@MainActor
private struct BeatLights: View {
    @ObservedObject var model: Metronome
    let width: CGFloat
    let maxDiameter: CGFloat
    let spacing: CGFloat
    var body: some View {
        let count = max(1, model.beats)
        let noAccent = model.beats == 0
        let playing = model.playing
        let current = model.currentBeat
        let beatTime = model.beatTime
        let bpm = model.bpm
        let palette = model.theme.palette
        let gap = count > 4 ? spacing / 2 : spacing
        let diameter = min(maxDiameter, (width - CGFloat(count - 1) * gap) / CGFloat(count))
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !noAccent || !playing)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - beatTime)
            let pulse = playing && current >= 0 && elapsed < min(0.14, (60 / Double(bpm)) * 0.45)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    let isCurrent = noAccent ? pulse : playing && current == index
                    let isPlayed = !noAccent && playing && current >= 0 && index < current
                    let color = isCurrent ? palette.playingBeat : palette.neutral
                    Circle()
                        .fill(isCurrent || isPlayed ? color : Color.clear)
                        .overlay(Circle().strokeBorder(color, lineWidth: min(2.5, max(1.25, diameter * 0.04))))
                        .frame(width: diameter, height: diameter)
                        .accessibilityLabel(noAccent ? "Unaccented beat" : "Beat \(index + 1) of \(count)")
                        .accessibilityValue(isCurrent ? "Current" : (isPlayed ? "Played" : "Upcoming"))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}


@MainActor
struct CompactReadout: View {
    @ObservedObject var model: Metronome
    var body: some View {
        HStack(spacing: 12) {
            TempoValue(model: model, fontSize: 26, width: 56, height: 32)
            BeatLights(model: model, width: 120, maxDiameter: 20, spacing: 6)
                .frame(width: 120, height: 32)

        }
        .frame(width: 188, height: 32)
    }
}

@MainActor
private struct ValueDragArea: NSViewRepresentable {
    let value: Int
    let bounds: ClosedRange<Int>
    let pointsPerStep: Double
    let onSet: (Int) -> Void
    let onDoubleClick: (() -> Void)?
    let onDragState: (Bool) -> Void
    func makeNSView(context: Context) -> ValueDragView {
        let view = ValueDragView()
        configure(view)
        return view
    }
    func updateNSView(_ view: ValueDragView, context: Context) { configure(view) }
    private func configure(_ view: ValueDragView) {
        view.value = value
        view.valueBounds = bounds
        view.pointsPerStep = pointsPerStep
        view.onSet = onSet
        view.onDoubleClick = onDoubleClick
        view.onDragState = onDragState
    }
    static func dismantleNSView(_ view: ValueDragView, coordinator: ()) { view.cancelInteraction() }
}

@MainActor
private final class ValueDragView: NSView {
    var value = 120
    var valueBounds = 30...252
    var pointsPerStep: Double = 3
    var onSet: ((Int) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragState: ((Bool) -> Void)?
    private var scrubber: ValueScrubber?
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
        scrubber = ValueScrubber(value: value, bounds: valueBounds, pointsPerStep: pointsPerStep)
    }
    override func mouseDragged(with event: NSEvent) {
        guard var state = scrubber else { return }
        let y = event.locationInWindow.y
        if !dragging {
            guard max(abs(y - pressY), abs(event.locationInWindow.x - pressX)) >= 3 else { return }
            dragging = true
            onDragState?(true)
        }
        let next = state.move(upwardPoints: Double(y - lastY))
        scrubber = state
        lastY = y
        if next != value { onSet?(next) }
    }
    override func mouseUp(with event: NSEvent) {
        guard scrubber != nil else { return }
        let wasDragging = dragging
        cancelInteraction()
        if !wasDragging && event.clickCount == 2 { onDoubleClick?() }
    }
    func cancelInteraction() {
        if dragging { onDragState?(false) }
        scrubber = nil
        dragging = false
    }
}
