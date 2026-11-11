import SwiftUI
import AppKit
import AVFoundation
import Darwin
import TempoCore

@main
@MainActor
struct MetronomApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var model = Metronome()
    @StateObject private var windows = WindowModes()
    var body: some Scene {
        WindowGroup("fdm-3") {
            InstrumentView(model: model, showWidget: { windows.showWidget() })
                .background(WindowBridge(windows: windows, model: model))
                .environment(\.instrumentTheme, model.theme)
        }
        .windowResizability(.contentSize)
        .commands {
            // Keep one instrument window; widget mode uses a companion panel.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Start / Stop") { model.toggle() }.keyboardShortcut(.space, modifiers: []).disabled(model.editingTempo)
                Button("Tap Tempo") { model.tap() }.keyboardShortcut("t", modifiers: []).disabled(model.editingTempo)
                Button("Mute / Unmute") { model.toggleMute() }.keyboardShortcut("m", modifiers: []).disabled(model.editingTempo)
                Button("Faster") { model.bpm += 1 }.keyboardShortcut(.upArrow, modifiers: []).disabled(model.editingTempo)
                Button("Slower") { model.bpm -= 1 }.keyboardShortcut(.downArrow, modifiers: []).disabled(model.editingTempo)
                Button("Faster by 10 BPM") { model.bpm += 10 }.keyboardShortcut(.rightArrow, modifiers: []).disabled(model.editingTempo)
                Button("Slower by 10 BPM") { model.bpm -= 10 }.keyboardShortcut(.leftArrow, modifiers: []).disabled(model.editingTempo)
                Button("Increase Beats") { model.adjustBeats(by: 1) }
                    .keyboardShortcut(.upArrow, modifiers: [.shift])
                    .disabled(model.editingTempo || model.beats == 9)
                Button("Decrease Beats") { model.adjustBeats(by: -1) }
                    .keyboardShortcut(.downArrow, modifiers: [.shift])
                    .disabled(model.editingTempo || model.beats == 0)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Widget Mode") { windows.toggle() }
                    .keyboardShortcut(.tab, modifiers: [])
                    .disabled(model.editingTempo)
            }
        }
    }
}

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    // A hidden instrument is normal in widget mode. Quit only on an explicit close.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
final class Metronome: ObservableObject {
    static let beatOptions = [0] + Array(2...9)
    @Published var bpm: Int { didSet {
        let bounded = Tempo.clamp(bpm)
        if bpm != bounded { bpm = bounded; return }
        UserDefaults.standard.set(bpm, forKey: "bpm"); restart()
    } }
    @Published var beats: Int { didSet { UserDefaults.standard.set(beats, forKey: "beats"); restart() } }
    @Published var subdivisions: Int { didSet { UserDefaults.standard.set(subdivisions, forKey: "subdivisions"); restart() } }
    @Published var sound: Int { didSet { UserDefaults.standard.set(sound, forKey: "sound"); restart() } }
    @Published var gap: Int {
        didSet { UserDefaults.standard.set(gap, forKey: "gap"); restart() }
    }
    @Published var theme: InstrumentTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            ThemedDockIcon.apply(theme)
        }
    }
    @Published var editingTempo = false
    private var lastAudibleVolume = 0.65
    @Published var volume: Double { didSet {
        if volume > 0 {
            lastAudibleVolume = volume
            UserDefaults.standard.set(volume, forKey: "lastAudibleVolume")
        }
        player.volume = Float(volume)
        UserDefaults.standard.set(volume, forKey: "volume")
    } }
    @Published private(set) var playing = false
    @Published private(set) var currentBeat = -1
    @Published private(set) var inSilentBar = false
    @Published private(set) var beatTime: TimeInterval = 0
    @Published private(set) var beatNumber = 0
    @Published var error: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var timer: Timer?
    private var nextFrame: Double = 0
    private var tick = 0
    private var gapSequence = GapSequence()
    private var generation = UUID()
    private var tapper = TapTempo()
    private var buffers: [AVAudioPCMBuffer] = []
    private var silentBuffers: [AVAudioPCMBuffer] = []
    private var activity: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["bpm": 120, "beats": 4, "subdivisions": 1, "sound": 0, "volume": 0.65])
        bpm = Tempo.clamp(defaults.integer(forKey: "bpm"))
        let savedBeats = min(9, max(0, defaults.integer(forKey: "beats")))
        beats = savedBeats == 1 ? 0 : savedBeats
        subdivisions = min(4, max(1, defaults.integer(forKey: "subdivisions")))
        sound = min(ClickVoice.allCases.count - 1, max(0, defaults.integer(forKey: "sound")))
        let savedVolume = min(1, max(0, defaults.double(forKey: "volume")))
        volume = savedVolume
        let savedAudibleVolume = defaults.double(forKey: "lastAudibleVolume")
        lastAudibleVolume = savedVolume > 0 ? savedVolume : (savedAudibleVolume > 0 ? min(1, savedAudibleVolume) : 0.65)
        theme = InstrumentTheme.restored(defaults.string(forKey: "theme"))
        let savedGap = defaults.integer(forKey: "gap")
        gap = GapCycle.options.contains(savedGap) ? savedGap : 0
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = Float(volume)
    }
    func adjustBeats(by delta: Int) {
        let index = Self.beatOptions.firstIndex(of: beats) ?? 0
        let next = min(Self.beatOptions.count - 1, max(0, index + delta))
        let value = Self.beatOptions[next]
        if value != beats { beats = value }
    }
    func toggle() { playing ? stop() : start() }
    func toggleMute() { volume = volume > 0 ? 0 : lastAudibleVolume }
    func tap() {
        if let tempo = tapper.tap(at: ProcessInfo.processInfo.systemUptime) { bpm = tempo }
    }
    private func restart() { if playing { stop(); start() } }
    func start() {
        guard !playing else { return }
        do {
            if !engine.isRunning { try engine.start() }
            generation = UUID()
            buffers = (0...2).map { makeClick(kind: $0) }
            silentBuffers = buffers.map { source in
                let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength)!
                silence.frameLength = source.frameLength
                silence.floatChannelData![0].update(repeating: 0, count: Int(source.frameLength))
                return silence
            }
            playing = true
            inSilentBar = false
            gapSequence = GapSequence()
            nextFrame = 0; tick = 0; currentBeat = -1; beatTime = 0; beatNumber = 0
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Playing metronome")
            // Audio sample times determine every click; the timer only replenishes the queue.
            schedule(until: 24_000)
            player.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08)))
            timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refill() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } catch {
            stop()
            self.error = "Audio could not start: \(error.localizedDescription)"
        }
    }
    func stop() {
        generation = UUID(); timer?.invalidate(); timer = nil
        player.stop(); playing = false; currentBeat = -1; beatTime = 0; inSilentBar = false
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    private func refill() {
        guard playing, let render = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: render) else { return }
        // Recover cleanly after a long scheduling stall rather than enqueueing past events.
        if nextFrame < Double(time.sampleTime) { stop(); start(); return }
        schedule(until: Double(time.sampleTime) + 24_000)
    }
    private func schedule(until horizon: Double) {
        let run = generation
        while nextFrame < horizon {
            let mainBeat = tick % subdivisions == 0
            let beat = beats == 0 ? 0 : (tick / subdivisions) % beats
            let kind = !mainBeat ? 2 : (beats > 0 && beat == 0 ? 0 : 1)
            let silent = gapSequence.isSilent(tick: tick, beats: beats, subdivisions: subdivisions, audibleBars: gap)
            let buffer = silent ? silentBuffers[kind] : buffers[kind]
            let frame = AVAudioFramePosition(nextFrame.rounded())
            player.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: frame, atRate: format.sampleRate), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                if mainBeat {
                    Task { @MainActor in
                        guard let self, self.playing, self.generation == run else { return }
                        self.beatTime = Date.timeIntervalSinceReferenceDate
                        self.beatNumber &+= 1
                        self.inSilentBar = silent
                        self.currentBeat = beat
                    }
                }
            }
            nextFrame += Tempo.frames(bpm: bpm, subdivisions: subdivisions, sampleRate: format.sampleRate)
            tick += 1
        }
    }
    private func makeClick(kind: Int) -> AVAudioPCMBuffer {
        let voice = ClickVoice(rawValue: sound) ?? .click
        let samples = voice.samples(kind: kind, sampleRate: format.sampleRate)
        let count = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

enum InstrumentTheme: String, CaseIterable {
    case charcoal, dracula, nord, gruvbox, githubLight, monokai, solarizedLight, desert, paperColorLight, peachpuff, tokyoNight
    var name: String {
        switch self {
        case .charcoal: return "Default"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .gruvbox: return "Gruvbox"
        case .githubLight: return "GitHub Light"
        case .monokai: return "Monokai"
        case .solarizedLight: return "Solarized Light"
        case .desert: return "Desert"
        case .paperColorLight: return "PaperColor Light"
        case .peachpuff: return "Peachpuff"
        case .tokyoNight: return "Tokyo Night"
        }
    }
    static var ordered: [InstrumentTheme] {
        [.charcoal] + allCases.filter { $0 != .charcoal }.sorted { $0.name < $1.name }
    }
    static func restored(_ value: String?) -> InstrumentTheme {
        if let value, let theme = InstrumentTheme(rawValue: value) { return theme }
        // Migrate preferences from the first, generic palette set.
        switch value {
        case "default": return .charcoal
        case "solarizedDark": return .solarizedLight
        case "midnight": return .nord
        case "forest": return .gruvbox
        case "burgundy": return .dracula
        case "white": return .githubLight
        default: return .charcoal
        }
    }
    var isLight: Bool { self == .githubLight || self == .solarizedLight || self == .paperColorLight || self == .peachpuff }
    var colorScheme: ColorScheme { isLight ? .light : .dark }
    var palette: InstrumentPalette { InstrumentPalette(theme: self) }
}

// All themes use the same modern six-role color hierarchy.
// The other surfaces, borders, and disabled states derive from these roles.
private struct ThemeColors {
    let background: UInt32
    let neutral: UInt32
    let tempo: UInt32
    let beat: UInt32
    let playingBeat: UInt32
    let action: UInt32
}

struct InstrumentPalette {
    let theme: InstrumentTheme
    private var colors: ThemeColors {
        switch theme {
        case .charcoal: return ThemeColors(background: 0x17191B, neutral: 0xF8F6F0, tempo: 0xF8F6F0, beat: 0xF8F6F0, playingBeat: 0xFF7D40, action: 0xFF7D40)
        case .dracula: return ThemeColors(background: 0x282A36, neutral: 0xF8F8F2, tempo: 0xBD93F9, beat: 0xFFB86C, playingBeat: 0x8BE9FD, action: 0x50FA7B)
        case .nord: return ThemeColors(background: 0x2E3440, neutral: 0xECEFF4, tempo: 0x88C0D0, beat: 0xB48EAD, playingBeat: 0x8FBCBB, action: 0xA3BE8C)
        case .gruvbox: return ThemeColors(background: 0x282828, neutral: 0xEBDBB2, tempo: 0xFABD2F, beat: 0xFE8019, playingBeat: 0x8EC07C, action: 0xB8BB26)
        case .githubLight: return ThemeColors(background: 0xFFFFFF, neutral: 0x24292F, tempo: 0x0969DA, beat: 0x953800, playingBeat: 0x8250DF, action: 0x1A7F37)
        case .monokai: return ThemeColors(background: 0x272822, neutral: 0xF8F8F2, tempo: 0xAE81FF, beat: 0xFD971F, playingBeat: 0x66D9EF, action: 0xA6E22E)
        case .solarizedLight: return ThemeColors(background: 0xFDF6E3, neutral: 0x586E75, tempo: 0x268BD2, beat: 0xCB4B16, playingBeat: 0x6C71C4, action: 0x168A81)
        case .desert: return ThemeColors(background: 0x333333, neutral: 0xFFFFFF, tempo: 0xFFA0A0, beat: 0xF0E68C, playingBeat: 0x98FB98, action: 0x87CEEB)
        case .paperColorLight: return ThemeColors(background: 0xEEEEEE, neutral: 0x444444, tempo: 0x005F87, beat: 0xAF0000, playingBeat: 0x008787, action: 0x5F8700)
        case .peachpuff: return ThemeColors(background: 0xFFDAB9, neutral: 0x000000, tempo: 0xA52A2A, beat: 0xC00058, playingBeat: 0x008080, action: 0x2E6F40)
        case .tokyoNight: return ThemeColors(background: 0x1A1B26, neutral: 0xC0CAF5, tempo: 0xFF9E64, beat: 0x7AA2F7, playingBeat: 0x7DCFFF, action: 0x9ECE6A)
        }
    }
    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
    var background: Color { color(colors.background) }
    var neutral: Color { color(colors.neutral) }
    var tempo: Color { color(colors.tempo) }
    var beat: Color { color(colors.beat) }
    var playingBeat: Color { color(colors.playingBeat) }
    var action: Color { color(colors.action) }
    private func surface(_ amount: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let base = Double((colors.background >> shift) & 255)
            let foreground = Double((colors.neutral >> shift) & 255)
            return (base + (foreground - base) * amount) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
    private func luminance(_ hex: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }
    var activeForeground: Color {
        let highlight = luminance(colors.action)
        func contrast(_ hex: UInt32) -> Double {
            let value = luminance(hex)
            return (max(highlight, value) + 0.05) / (min(highlight, value) + 0.05)
        }
        return contrast(colors.background) >= contrast(colors.neutral) ? background : neutral
    }
    var controlTop: Color { surface(0.12) }
    var controlBottom: Color { controlTop }
    var recess: Color { surface(0.035) }
    var fieldBorder: Color { neutral.opacity(0.12) }
    var bodyColors: [Color] { [background, background] }
}

private struct InstrumentThemeKey: EnvironmentKey {
    static let defaultValue: InstrumentTheme = .charcoal
}

extension EnvironmentValues {
    var instrumentTheme: InstrumentTheme {
        get { self[InstrumentThemeKey.self] }
        set { self[InstrumentThemeKey.self] = newValue }
    }
}


@MainActor
private enum ThemedDockIcon {
    static func apply(_ theme: InstrumentTheme) {
        let palette = theme.palette
        let colors = InstrumentIconColors(
            background: NSColor(palette.background),
            neutral: NSColor(palette.neutral),
            playingBeat: NSColor(palette.playingBeat)
        )
        NSApp.applicationIconImage = InstrumentIconArtwork.make(colors: colors)
    }
}

struct InstrumentButtonStyle: ButtonStyle {
    @Environment(\.instrumentTheme) private var theme
    private var palette: InstrumentPalette { theme.palette }
    var accent = false
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(accent ? palette.activeForeground : palette.neutral)
            .background(
                LinearGradient(
                    colors: accent ? [palette.action, palette.action] : [palette.controlTop, palette.controlBottom],
                    startPoint: .top, endPoint: .bottom
                ), in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(accent ? palette.action : palette.fieldBorder, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

// Inline numeric entry shares the tempo readout's size, alignment, and weight.
@MainActor
struct InlineTempoField: NSViewRepresentable {
    let bpm: Int
    let color: Color
    let fontSize: CGFloat
    let onSet: (Int) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: String(bpm))
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.maximumNumberOfLines = 1
        field.formatter = TempoInputFormatter()
        field.cell?.isScrollable = true
        field.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = NSColor(color)
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Tempo in beats per minute")
        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        field.textColor = NSColor(color)
        // Preserve the user's draft while playback refreshes the readout.
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTempoField
        private var finished = false
        init(parent: InlineTempoField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let field = control as? NSTextField else { return false }
            if selector == NSSelectorFromString("insertNewline:") {
                finish(field, apply: true)
                return true
            }
            if selector == NSSelectorFromString("cancelOperation:") {
                finish(field, apply: false)
                return true
            }
            return false
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField { finish(field, apply: true) }
        }
        private func finish(_ field: NSTextField, apply: Bool) {
            guard !finished else { return }
            finished = true
            let window = field.window
            if apply, let value = Tempo.fromText(field.stringValue) {
                parent.onSet(value)
            } else {
                parent.onCancel()
            }
            window?.makeFirstResponder(nil)
        }
    }
}

// AppKit validates every proposed edit, including paste, before displaying it.
// Empty text stays valid while editing so users can delete and replace a value.
final class TempoInputFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        if let string = obj as? String { return string }
        if let number = obj as? NSNumber { return number.stringValue }
        return nil
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard Tempo.isValidDraft(string) else { return false }
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        Tempo.isValidDraft(partialString)
    }
}

struct DropdownChoice {
    let id: String
    let label: String
}

// A SwiftUI button renders the complete label. AppKit supplies only the popup
// menu, avoiding macOS Menu styles reducing a custom label to its first Text.
@MainActor
struct ChoiceDropdown: View {
    @Environment(\.instrumentTheme) private var theme
    @StateObject private var presenter = ChoiceMenuPresenter()
    let title: String
    let selectedID: String
    let selectedLabel: String
    let options: [DropdownChoice]
    let onSelect: (String) -> Void
    private var palette: InstrumentPalette { theme.palette }
    var body: some View {
        Button {
            presenter.show(options: options, selectedID: selectedID, onSelect: onSelect)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold)).tracking(1)
                    .foregroundColor(palette.neutral.opacity(0.65))
                HStack(spacing: 6) {
                    Text(selectedLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.neutral.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(palette.neutral.opacity(0.65))
                }
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48, alignment: .leading)
            .background(palette.recess, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.fieldBorder))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .background(ChoiceMenuAnchor(presenter: presenter))
        .accessibilityLabel(title)
        .accessibilityValue(selectedLabel)
    }
}

@MainActor
final class ChoiceMenuPresenter: NSObject, ObservableObject {
    weak var anchor: NSView?
    private var selection: ((String) -> Void)?
    func show(options: [DropdownChoice], selectedID: String, onSelect: @escaping (String) -> Void) {
        guard let anchor, anchor.window != nil else { return }
        let menu = NSMenu()
        menu.minimumWidth = anchor.bounds.width
        for option in options {
            let item = NSMenuItem(title: option.label, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.id
            item.state = option.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        selection = onSelect
        let y = anchor.isFlipped ? anchor.bounds.maxY + 4 : anchor.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: anchor)
        selection = nil
    }
    @objc private func choose(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { selection?(id) }
    }
}

@MainActor
struct ChoiceMenuAnchor: NSViewRepresentable {
    let presenter: ChoiceMenuPresenter
    func makeNSView(context: Context) -> ChoiceAnchorView {
        let view = ChoiceAnchorView()
        presenter.anchor = view
        return view
    }
    func updateNSView(_ nsView: ChoiceAnchorView, context: Context) { presenter.anchor = nsView }
}

@MainActor
final class ChoiceAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
struct SubdivisionSelector: View {
    @Binding var value: Int
    private let labels = ["Quarter notes", "Eighth notes", "Triplets", "16th notes"]
    var body: some View {
        ChoiceDropdown(
            title: "SUBDIVISION", selectedID: String(value),
            selectedLabel: labels[min(3, max(0, value - 1))],
            options: labels.enumerated().map { DropdownChoice(id: String($0.offset + 1), label: $0.element) }
        ) { id in
            if let number = Int(id), (1...4).contains(number) { value = number }
        }
    }
}

@MainActor
struct InstrumentView: View {
    @ObservedObject var model: Metronome
    var showWidget: () -> Void
    @State private var showingSettings = false
    private var palette: InstrumentPalette { model.theme.palette }
    var body: some View {
        VStack(spacing: 28) {
            header
            ModernReadout(model: model).frame(height: DisplayGeometry.mainHeight)
            HStack(spacing: 8) {
                Button { model.bpm = Tempo.clamp(model.bpm - 1) } label: {
                    Image(systemName: "minus").frame(width: 24, height: 28)
                }
                .buttonStyle(.plain).foregroundColor(palette.neutral)
                .help("Decrease tempo").accessibilityLabel("Decrease tempo")
                Slider(value: Binding(
                    get: { Double(model.bpm) },
                    set: { value in
                        let bpm = Tempo.clamp(Int(value.rounded()))
                        if model.bpm != bpm { model.bpm = bpm }
                    }), in: 30...252, step: 1)
                    .tint(palette.tempo)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(model.bpm) beats per minute")
                Button { model.bpm = Tempo.clamp(model.bpm + 1) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 28)
                }
                .buttonStyle(.plain).foregroundColor(palette.neutral)
                .help("Increase tempo").accessibilityLabel("Increase tempo")
            }
            .frame(height: 28)
            HStack(spacing: 8) {
                beatButton(delta: -1)
                beatButton(delta: 1)
                Button { model.toggleMute() } label: {
                    Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 16)).frame(width: 44, height: 44)
                }
                .buttonStyle(InstrumentButtonStyle(radius: 10))
                .help(model.volume == 0 ? "Unmute (M)" : "Mute (M)")
                .accessibilityLabel(model.volume == 0 ? "Unmute" : "Mute")
                Button { model.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.playing ? "stop.fill" : "play.fill")
                        Text(model.playing ? "Stop" : "Start")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(InstrumentButtonStyle(accent: true, radius: 10))
                .help("Start / Stop (Space)")
                .accessibilityLabel(model.playing ? "Stop metronome" : "Start metronome")
            }
        }
        .padding(24).frame(width: 380)
        .background(palette.background)
        .preferredColorScheme(model.theme.colorScheme)
        .alert("Audio unavailable", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("fdm-3")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .tracking(-0.5).foregroundColor(palette.action)
            Spacer(minLength: 8)
            Button { model.tap() } label: {
                Text("TAP").font(.system(size: 11, weight: .semibold)).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain).foregroundColor(palette.neutral)
            .help("Tap tempo (T)").accessibilityLabel("Tap tempo")
            Button { showingSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 28, height: 32)
            }
            .buttonStyle(.plain).foregroundColor(palette.neutral)
            .help("Settings").accessibilityLabel("Settings")
            .popover(isPresented: $showingSettings, arrowEdge: .trailing) {
                InstrumentSettings(model: model)
                    .environment(\.instrumentTheme, model.theme)
                    .preferredColorScheme(model.theme.colorScheme)
            }
            Button(action: showWidget) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 15)).frame(width: 28, height: 32)
            }
            .buttonStyle(.plain).foregroundColor(palette.neutral)
            .help("Widget mode (Tab or \\)").accessibilityLabel("Enter widget mode")
        }
        .frame(height: 32)
    }
    private func beatButton(delta: Int) -> some View {
        let atLimit = delta < 0 ? model.beats == 0 : model.beats == 9
        return Button { model.adjustBeats(by: delta) } label: {
            Image(systemName: delta < 0 ? "chevron.down" : "chevron.up")
                .font(.system(size: 15, weight: .medium)).frame(width: 44, height: 44)
        }
        .buttonStyle(InstrumentButtonStyle(radius: 10))
        .disabled(atLimit).opacity(atLimit ? 0.4 : 1)
        .help(delta < 0 ? "Decrease beats (Shift + ↓)" : "Increase beats (Shift + ↑)")
        .accessibilityLabel(delta < 0 ? "Decrease beats" : "Increase beats")
        .accessibilityValue(model.beats == 0 ? "No accent" : "\(model.beats) beats per bar")
    }
}

@MainActor
struct InstrumentSettings: View {
    @ObservedObject var model: Metronome
    private var palette: InstrumentPalette { model.theme.palette }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.neutral)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    SubdivisionSelector(value: $model.subdivisions)
                    gapSelector
                }
                HStack(spacing: 8) {
                    soundSelector
                    themeSelector
                }
            }
            HStack(spacing: 10) {
                Button { model.toggleMute() } label: {
                    Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 12))
                        .foregroundColor(palette.neutral)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(model.volume == 0 ? "Unmute (M)" : "Mute (M)")
                .accessibilityLabel(model.volume == 0 ? "Unmute" : "Mute")
                Slider(value: $model.volume, in: 0...1)
                    .tint(palette.action).controlSize(.small).accessibilityLabel("Volume")
            }
        }
        .padding(16).frame(width: 300)
        .background(LinearGradient(colors: palette.bodyColors,
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var gapSelector: some View {
        ChoiceDropdown(
            title: "GAP", selectedID: String(model.gap),
            selectedLabel: GapCycle.label(for: model.gap),
            options: GapCycle.options.map {
                DropdownChoice(id: String($0), label: GapCycle.label(for: $0))
            }
        ) { id in
            if let gap = Int(id), GapCycle.options.contains(gap) { model.gap = gap }
        }
    }

    private var soundSelector: some View {
        ChoiceDropdown(
            title: "SOUND", selectedID: String(model.sound),
            selectedLabel: (ClickVoice(rawValue: model.sound) ?? .click).name,
            options: ClickVoice.allCases.map { DropdownChoice(id: String($0.rawValue), label: $0.name) }
        ) { id in
            if let sound = Int(id) { model.sound = sound }
        }
    }

    private var themeSelector: some View {
        ChoiceDropdown(
            title: "THEME", selectedID: model.theme.rawValue,
            selectedLabel: model.theme.name,
            options: InstrumentTheme.ordered.map { DropdownChoice(id: $0.rawValue, label: $0.name) }
        ) { id in
            if let theme = InstrumentTheme(rawValue: id) { model.theme = theme }
        }
    }


}

// Route transport and tempo shortcuts before focused controls consume them.
// This monitor is local to this app and does not require accessibility permission.
@MainActor
final class WindowModes: ObservableObject {
    // Retain the instrument so it can always be restored after being hidden.
    private var mainWindow: NSWindow?
    private enum Mode { case instrument, widget }
    private var mode: Mode = .instrument
    private weak var model: Metronome?
    private var widget: TempoPanel?
    private var keyMonitor: Any?
    private var closeObserver: NSObjectProtocol?

    func attach(window: NSWindow, model: Metronome) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.isReleasedWhenClosed = false
        self.model = model
        // Apply the saved theme on launch; later theme changes refresh the Dock immediately.
        ThemedDockIcon.apply(model.theme)
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .instrument else { return }
                self.model?.stop()
                self.widget?.orderOut(nil)
                NSApp.terminate(nil)
            }
        }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model?.editingTempo != true,
                  event.window === self.mainWindow || event.window === self.widget
            else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // Match the typed backslash character, including layouts that use Option for it.
            if event.characters == "\\", modifiers.intersection([.command, .control]).isEmpty {
                if !event.isARepeat { self.toggle() }
                return nil
            }
            if modifiers == [.shift] {
                switch event.keyCode {
                case 126: self.model?.adjustBeats(by: 1)
                case 125: self.model?.adjustBeats(by: -1)
                default: return event
                }
                return nil
            }
            guard modifiers.isEmpty else { return event }
            if event.charactersIgnoringModifiers?.lowercased() == "m" {
                if !event.isARepeat { self.model?.toggleMute() }
                return nil
            }
            switch event.keyCode {
            case 48: // Tab switches window mode before focus navigation consumes it.
                if !event.isARepeat { self.toggle() }
            case 49: // Space overrides focused button activation.
                if !event.isARepeat { self.model?.toggle() }
            case 123: // Left overrides a focused slider or picker.
                self.model?.bpm -= 10
            case 124: // Right
                self.model?.bpm += 10
            case 126: // Up
                self.model?.bpm += 1
            case 125: // Down
                self.model?.bpm -= 1
            default:
                return event
            }
            return nil
        }
    }

    func toggle() {
        if mode == .widget { showInstrument() } else { showWidget() }
    }

    func showWidget() {
        guard let model, let mainWindow else { return }
        if widget == nil {
            let panel = TempoPanel(
                contentRect: NSRect(x: 0, y: 0, width: DisplayGeometry.widgetWidth, height: DisplayGeometry.widgetHeight),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.title = "fdm-3 Tempo"
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: TempoWidget(
                model: model, showInstrument: { [weak self] in self?.showInstrument() }
            ))
            widget = panel
            let topLeft = NSPoint(x: mainWindow.frame.minX, y: mainWindow.frame.maxY)
            panel.setFrameTopLeftPoint(topLeft)
        }
        // Show the replacement before hiding the instrument: never leave no visible window.
        mode = .widget
        widget?.makeKeyAndOrderFront(nil)
        mainWindow.orderOut(nil)
    }

    func showInstrument() {
        guard let mainWindow else { return }
        mainWindow.makeKeyAndOrderFront(nil)
        mode = .instrument
        widget?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class TempoPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
struct TempoWidget: View {
    @ObservedObject var model: Metronome
    private var palette: InstrumentPalette { model.theme.palette }
    var showInstrument: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            ModernReadout(model: model)
                .frame(width: DisplayGeometry.widgetDisplayWidth, height: DisplayGeometry.widgetDisplayHeight)
            VStack(spacing: 6) {
                Circle()
                    .fill(model.playing ? palette.action : palette.neutral.opacity(0.18))
                    .frame(width: 9, height: 9)
                    .frame(width: 28, height: 28)
                    .help(model.playing ? "Metronome is playing" : "Metronome is stopped")
                    .accessibilityLabel("Playback status")
                    .accessibilityValue(model.playing ? "Playing" : "Stopped")

                Button(action: showInstrument) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(InstrumentButtonStyle(radius: 8))
                .help("Return to fdm-3 (Tab or \\)")
                .accessibilityLabel("Return to full fdm-3 window")
            }
        }
        .padding(.horizontal, 10).frame(width: DisplayGeometry.widgetWidth, height: DisplayGeometry.widgetHeight)
        .background(LinearGradient(colors: palette.bodyColors,
                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.neutral.opacity(0.10)))
        .contextMenu {
            Button(model.playing ? "Stop" : "Start") { model.toggle() }
            Button("Tap Tempo") { model.tap() }
            Divider()
            Button("Show Full fdm-3") { showInstrument() }
                .keyboardShortcut(.tab, modifiers: [])
                    .disabled(model.editingTempo)
            Divider()
            Button("Quit fdm-3") { model.stop(); NSApp.terminate(nil) }
        }
        .environment(\.instrumentTheme, model.theme)
        .help("Drag the background to move. Drag BPM up/down to adjust it. Click expand to return to fdm-3.")
        .preferredColorScheme(model.theme.colorScheme)
    }
}

@MainActor
struct WindowBridge: NSViewRepresentable {
    let windows: WindowModes
    let model: Metronome
    func makeNSView(context: Context) -> WindowAttachment {
        let view = WindowAttachment()
        view.onWindow = { window in windows.attach(window: window, model: model) }
        return view
    }
    func updateNSView(_ nsView: WindowAttachment, context: Context) {}
}

@MainActor
final class WindowAttachment: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}
