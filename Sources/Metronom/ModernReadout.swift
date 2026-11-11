import SwiftUI
import AppKit
import TempoCore

enum DisplayGeometry {
    static let width: CGFloat = 468
    static let mainHeight: CGFloat = 234
    static let mainBeatDiameter: CGFloat = 68
    static let mainBeatSpacing: CGFloat = 24
    // Match the outer metric centers to beats 1 and 4 of the reference row.
    static let metricColumnWidth: CGFloat = 1.5 * (mainBeatDiameter + mainBeatSpacing)
    static let widgetScale: CGFloat = 1.15
    static let widgetWidth: CGFloat = 266 * widgetScale
    static let widgetHeight: CGFloat = 40 * widgetScale
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
    @ViewBuilder
    private var gapValue: some View {
        if model.gap == GapCycle.random {
            Image(systemName: "shuffle")
        } else if model.gap == 0 {
            Image(systemName: "circle.slash")
                .font(.system(size: 26, weight: .regular)).opacity(0.65)
        } else {
            Text(String(model.gap)).monospacedDigit()
        }
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
            let column = DisplayGeometry.metricColumnWidth * scale
            VStack(spacing: 0) {
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
                        gapValue
                            .font(.system(size: 52 * scale, weight: .regular))
                            .foregroundColor(palette.gap)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .frame(width: column - 8 * scale, height: 94 * scale)
                        caption("GAP", scale: scale)
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
                    .accessibilityLabel("Gap")
                    .accessibilityValue(gapDescription)
                    .accessibilityAdjustableAction { direction in
                        setGap(index: gapIndex + (direction == .increment ? 1 : -1))
                    }
                }
                .frame(width: DisplayGeometry.width * scale, height: 112 * scale)
                .padding(.bottom, 28 * scale)
                BeatLights(model: model, width: DisplayGeometry.width * scale, maxDiameter: DisplayGeometry.mainBeatDiameter * scale, spacing: DisplayGeometry.mainBeatSpacing * scale)
                    .frame(height: 68 * scale)
                // An unconditional slot keeps the beat and metric rows fixed.
                Color.clear
                    .frame(width: DisplayGeometry.width * scale, height: 8 * scale)
                    .overlay {
                        if model.gap != 0 { BarSequenceDots(model: model, scale: scale) }
                    }
                    .padding(.top, 18 * scale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
    private func caption(_ title: String, scale: CGFloat) -> some View {
        Text(title).font(.system(size: 10 * scale, weight: .medium))
            .tracking(1.4 * scale).foregroundColor(palette.neutral.opacity(0.65))
            .lineLimit(1).frame(height: 16 * scale)
    }
}

@MainActor
private struct BarSequenceDots: View {
    @ObservedObject var model: Metronome
    let scale: CGFloat
    private var neutral: Color { model.theme.palette.neutral }
    var body: some View {
        let audible = model.sequenceAudibleBars
        let total = audible + model.sequenceSilentBars
        let current = model.sequenceCurrentBar
        let random = model.gap == GapCycle.random
        let currentSilent = current >= audible && current >= 0 ? current - audible : -1
        return HStack(spacing: 8 * scale) {
            if random {
                // A fixed-width unknown run never reveals its randomly chosen length.
                Image(systemName: "shuffle").font(.system(size: 9 * scale))
                    .foregroundColor(neutral.opacity(current >= 0 && currentSilent < 0 ? 1 : 0.55))
                ForEach(0..<model.sequenceSilentBars, id: \.self) { index in
                    Circle()
                        .fill(neutral.opacity(index == currentSilent ? 1 : 0.18))
                        .frame(width: 7 * scale, height: 7 * scale)
                }
            } else {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(neutral.opacity(index == current ? 1 : (index < audible ? 0.55 : 0.18)))
                        .frame(width: 7 * scale, height: 7 * scale)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gap bar sequence")
        .accessibilityValue(random
            ? (currentSilent >= 0
                ? "Silent bar \(currentSilent + 1) of \(model.sequenceSilentBars)."
                : "Random audible run, length hidden; followed by \(model.sequenceSilentBars) silent bars.")
            : (current >= 0
                ? "Bar \(current + 1) of \(total), \(current < audible ? "audible" : "silent"). \(audible) audible and \(model.sequenceSilentBars) silent bars."
                : "\(audible) audible and \(model.sequenceSilentBars) silent bars."))
        .help(random
            ? "The random audible run stays hidden. Dots show the silent bars; brightest marks the current bar."
            : "Each small dot is one bar. Brightest: current; softer: audible; faint: silent.")
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
                .font(.system(size: fontSize, weight: .regular))
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
    var halfFillSilentBars = false
    var body: some View {
        // Preview meter edits immediately while audio completes the current bar.
        let count = max(1, model.beats)
        let playing = model.playing
        let silent = halfFillSilentBars && playing && model.inSilentBar
        let accent = model.accent
        let current = model.currentBeat >= 0 ? model.currentBeat % count : -1
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
                    let hasAccent = accent && index == 0
                    let isAccented = hasAccent
                    let color = isAccented ? palette.action : (isCurrent ? palette.playingBeat : palette.neutral)
                    let highlight = LinearGradient(
                        colors: isAccented && isCurrent ? [palette.action, palette.playingBeat] : [color, color],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(highlight)
                        .mask(alignment: hasAccent ? .top : .bottom) {
                            Rectangle().frame(height: silent ? diameter / 2 : diameter)
                        }
                        .opacity(isCurrent || isPlayed ? 1 : 0)
                        .overlay(Circle().strokeBorder(highlight, lineWidth: min(2.5, max(1.25, diameter * 0.04)))
                            .opacity(isCurrent || isPlayed ? 1 : outlineOpacity))
                        .frame(width: diameter, height: diameter)
                        .accessibilityLabel("\(hasAccent ? "Accented beat" : "Beat") \(index + 1) of \(count)")
                        .accessibilityValue((silent ? "Silent gap, " : "") + (isCurrent ? "Current" : (isPlayed ? "Played" : "Upcoming")))
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
        let beatWidth: CGFloat = 104
        return HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(model.bpm))
                    .font(.system(size: 26, weight: .regular)).monospacedDigit()
                    .foregroundColor(model.theme.palette.tempo)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(model.bpm) beats per minute")
                Text("bpm").font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(model.theme.palette.neutral.opacity(0.65))
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: 72, height: 32)
            BeatLights(model: model, width: beatWidth, maxDiameter: 20, spacing: 5, outlineOpacity: 0.8, halfFillSilentBars: true)
                .frame(width: beatWidth, height: 32)
        }
        .frame(width: 186, height: 32)
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

