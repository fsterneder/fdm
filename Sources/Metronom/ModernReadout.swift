import SwiftUI
import AppKit
import TempoCore

enum DisplayGeometry {
    static let width: CGFloat = 468
    static let mainHeight: CGFloat = 208
    static let widgetWidth: CGFloat = 244
    static let widgetHeight: CGFloat = 40
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
    private var gapIndex: Int { GapCycle.options.firstIndex(of: model.gap) ?? 0 }
    private var gapText: String {
        if model.inSilentBar { return "\(model.gapBarsRemaining)/\(model.playbackGapBars)" }
        if model.gap == 0 { return "Off" }
        if model.gap == GapCycle.random { return "Rnd" }
        return String(model.gap)
    }
    private var gapDescription: String {
        if model.gap == 0 { return "Gap off" }
        if model.gap == GapCycle.random { return "Randomly choose 1, 2, or 4 audible bars before silence" }
        return "\(model.gap) audible \(model.gap == 1 ? "bar" : "bars") before silence"
    }
    private func setGap(index: Int) {
        let bounded = min(GapCycle.options.count - 1, max(0, index))
        let value = GapCycle.options[bounded]
        if model.gap != value { model.gap = value }
    }
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / DisplayGeometry.width,
                            geometry.size.height / DisplayGeometry.mainHeight)
            let column = DisplayGeometry.width / 3 * scale
            VStack(spacing: 28 * scale) {
                HStack(spacing: 0) {
                    VStack(spacing: 2 * scale) {
                        TempoValue(model: model, fontSize: 68 * scale, width: column, height: 94 * scale)
                        caption("BPM", scale: scale)
                    }
                    .frame(width: column)
                    VStack(spacing: 2 * scale) {
                        Text(subdivisionText)
                            .font(.system(size: 52 * scale, weight: .regular))
                            .monospacedDigit().foregroundColor(palette.beat)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .frame(width: column - 8 * scale, height: 94 * scale)
                        caption("SUBDIVISION", scale: scale)
                    }
                    .frame(width: column)
                    .overlay {
                        ValueDragArea(value: model.subdivisions, bounds: 1...4, pointsPerStep: 12,
                            onSet: { value in
                                if model.subdivisions != value { model.subdivisions = value }
                            }, onDoubleClick: nil, onDragState: { model.editingTempo = $0 })
                            .frame(width: column, height: 112 * scale)
                            .accessibilityHidden(true)
                    }
                    .help("Drag up/down to change subdivision.")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Subdivision")
                    .accessibilityValue("\(model.subdivisions) clicks per beat")
                    VStack(spacing: 2 * scale) {
                        Text(gapText)
                            .font(.system(size: 52 * scale, weight: .regular))
                            .monospacedDigit().foregroundColor(palette.gap)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .frame(width: column - 8 * scale, height: 94 * scale)
                        caption(model.inSilentBar ? "SILENT" : "GAP", scale: scale)
                    }
                    .frame(width: column)
                    .overlay {
                        ValueDragArea(value: gapIndex, bounds: 0...(GapCycle.options.count - 1), pointsPerStep: 12,
                            onSet: { setGap(index: $0) }, onDoubleClick: nil,
                            onDragState: { model.editingTempo = $0 })
                            .frame(width: column, height: 112 * scale)
                            .accessibilityHidden(true)
                    }
                    .help("\(gapDescription). Drag up/down: Off, 1, 2, 4, Random.")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.inSilentBar ? "Silent bars remaining; gap setting" : "Gap")
                    .accessibilityValue(model.inSilentBar
                        ? "\(model.gapBarsRemaining) of \(model.playbackGapBars) silent bars remaining. \(gapDescription)"
                        : gapDescription)
                    .accessibilityAdjustableAction { direction in
                        setGap(index: gapIndex + (direction == .increment ? 1 : -1))
                    }
                }
                .frame(height: 112 * scale)
                BeatLights(model: model, width: DisplayGeometry.width * scale, maxDiameter: 68 * scale, spacing: 24 * scale)
                    .frame(height: 68 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }
    private func caption(_ title: String, scale: CGFloat) -> some View {
        Text(title).font(.system(size: 10 * scale, weight: .medium))
            .tracking(1.4 * scale).foregroundColor(palette.neutral.opacity(0.65))
            .lineLimit(1).frame(height: 16 * scale)
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
    var outlineOpacity: Double = 1
    var body: some View {
        let count = max(1, model.playbackBeats)
        let playing = model.playing
        let accent = model.playbackAccent
        let current = model.currentBeat
        let beatTime = model.beatTime
        let bpm = model.playbackBPM
        let palette = model.theme.palette
        let gap = count > 4 ? spacing / 2 : spacing
        let diameter = min(maxDiameter, (width - CGFloat(count - 1) * gap) / CGFloat(count))
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: count != 1 || !playing)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - beatTime)
            let pulse = playing && current >= 0 && elapsed < min(0.14, (60 / Double(bpm)) * 0.45)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    let isCurrent = count == 1 ? pulse : playing && current == index
                    let isPlayed = count > 1 && playing && current >= 0 && index < current
                    let isAccented = accent && index == 0
                    let color = isAccented ? palette.action : (isCurrent ? palette.playingBeat : palette.neutral)
                    Circle()
                        .fill(isCurrent || isPlayed ? color : Color.clear)
                        .overlay(Circle().strokeBorder(color.opacity(isCurrent || isPlayed ? 1 : outlineOpacity), lineWidth: min(2.5, max(1.25, diameter * 0.04))))
                        .frame(width: diameter, height: diameter)
                        .accessibilityLabel("\(isAccented ? "Accented beat" : "Beat") \(index + 1) of \(count)")
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
        let beatWidth: CGFloat = model.bpm >= 100 ? 100 : 104
        return HStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(model.bpm))
                    .font(.system(size: 26, weight: .semibold)).monospacedDigit()
                    .foregroundColor(model.theme.palette.tempo)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(model.bpm) beats per minute")
                Text("bpm").font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(model.theme.palette.neutral.opacity(0.65))
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: true, vertical: false)
            BeatLights(model: model, width: beatWidth, maxDiameter: 20, spacing: 5, outlineOpacity: 0.8)
                .frame(width: beatWidth, height: 32)
        }
        .padding(.leading, 8)
        .frame(width: 188, height: 32, alignment: .leading)
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

