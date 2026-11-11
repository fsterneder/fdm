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
                Button("Faster") { model.bpm += 1 }.keyboardShortcut(.upArrow, modifiers: []).disabled(model.editingTempo)
                Button("Slower") { model.bpm -= 1 }.keyboardShortcut(.downArrow, modifiers: []).disabled(model.editingTempo)
                Button("Faster by 10 BPM") { model.bpm += 10 }.keyboardShortcut(.rightArrow, modifiers: []).disabled(model.editingTempo)
                Button("Slower by 10 BPM") { model.bpm -= 10 }.keyboardShortcut(.leftArrow, modifiers: []).disabled(model.editingTempo)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Widget Mode") { windows.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
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
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
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

struct InstrumentPalette {
    let theme: InstrumentTheme
    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
    var ink: Color {
        switch theme {
        case .charcoal: return Color(red: 0.055, green: 0.063, blue: 0.067)
        case .dracula: return color(0x282A36)
        case .nord: return color(0x2E3440)
        case .gruvbox: return color(0x282828)
        case .githubLight: return color(0xFFFFFF)
        case .monokai: return color(0x272822)
        case .solarizedLight: return color(0xFDF6E3)
        case .desert: return color(0x333333)
        case .paperColorLight: return color(0xEEEEEE)
        case .peachpuff: return color(0xFFDAB9)
        case .tokyoNight: return color(0x1A1B26)
        }
    }
    var panel: Color {
        switch theme {
        case .charcoal: return Color(red: 0.105, green: 0.117, blue: 0.122)
        case .dracula: return color(0x44475A)
        case .nord: return color(0x3B4252)
        case .gruvbox: return color(0x3C3836)
        case .githubLight: return color(0xF6F8FA)
        case .monokai: return color(0x3E3D32)
        case .solarizedLight: return color(0xEEE8D5)
        case .desert: return color(0x4D4D4D)
        case .paperColorLight: return color(0xE4E4E4)
        case .peachpuff: return color(0xF5C195)
        case .tokyoNight: return color(0x292E42)
        }
    }
    var accent: Color {
        switch theme {
        case .charcoal: return Finish.orange
        case .dracula: return color(0xBD93F9)
        case .nord: return color(0x88C0D0)
        case .gruvbox: return color(0xFABD2F)
        case .githubLight: return color(0x0969DA)
        case .monokai: return color(0xA6E22E)
        case .solarizedLight: return color(0x2AA198)
        case .desert: return color(0xF0E68C)
        case .paperColorLight: return color(0x005F87)
        case .peachpuff: return color(0xA52A2A)
        case .tokyoNight: return color(0x7AA2F7)
        }
    }
    var foreground: Color {
        switch theme {
        case .charcoal: return .white
        case .dracula: return color(0xF8F8F2)
        case .nord: return color(0xECEFF4)
        case .gruvbox: return color(0xEBDBB2)
        case .githubLight: return color(0x24292F)
        case .monokai: return color(0xF8F8F2)
        case .solarizedLight: return color(0x586E75)
        case .desert: return color(0xFFFFFF)
        case .paperColorLight: return color(0x444444)
        case .peachpuff: return color(0x000000)
        case .tokyoNight: return color(0xC0CAF5)
        }
    }
    var muted: Color {
        switch theme {
        case .charcoal: return Color(red: 0.52, green: 0.56, blue: 0.56)
        case .dracula: return color(0x8BE9FD)
        case .nord: return color(0xD8DEE9)
        case .gruvbox: return color(0xBDAE93)
        case .githubLight: return color(0x57606A)
        case .monokai: return color(0xCFCFC2)
        case .solarizedLight: return color(0x586E75)
        case .desert: return color(0x6DCEEB)
        case .paperColorLight: return color(0x005F87)
        case .peachpuff: return color(0x406090)
        case .tokyoNight: return color(0xA9B1D6)
        }
    }
    var controlTop: Color {
        switch theme {
        case .charcoal: return Color(white: 0.23)
        case .dracula: return color(0x44475A)
        case .nord: return color(0x434C5E)
        case .gruvbox: return color(0x3C3836)
        case .githubLight: return color(0xFFFFFF)
        case .monokai: return color(0x414339)
        case .solarizedLight: return color(0xEEE8D5)
        case .desert: return color(0x666666)
        case .paperColorLight: return color(0xE4E4E4)
        case .peachpuff: return color(0xF5C195)
        case .tokyoNight: return color(0x292E42)
        }
    }
    var controlBottom: Color {
        switch theme {
        case .charcoal: return Color(white: 0.16)
        case .dracula: return color(0x44475A)
        case .nord: return color(0x434C5E)
        case .gruvbox: return color(0x3C3836)
        case .githubLight: return color(0xFFFFFF)
        case .monokai: return color(0x414339)
        case .solarizedLight: return color(0xEEE8D5)
        case .desert: return color(0x666666)
        case .paperColorLight: return color(0xE4E4E4)
        case .peachpuff: return color(0xF5C195)
        case .tokyoNight: return color(0x292E42)
        }
    }
    var recess: Color { theme == .charcoal ? ink.opacity(0.65) : panel }
    var border: Color { theme.isLight ? .black : .white }
    var fieldBorder: Color {
        switch theme {
        case .charcoal: return border.opacity(0.06)
        case .dracula: return color(0x6272A4)
        case .nord: return color(0x4C566A)
        case .gruvbox: return color(0x665C54)
        case .githubLight: return color(0xD0D7DE)
        case .monokai: return color(0x75715E)
        case .solarizedLight: return color(0x93A1A1)
        case .desert: return color(0x7F7F8C)
        case .paperColorLight: return color(0xBCBCBC)
        case .peachpuff: return color(0xDFBA99)
        case .tokyoNight: return color(0x545C7E)
        }
    }
    var activeForeground: Color {
        switch theme {
        case .githubLight, .paperColorLight, .peachpuff: return .white
        case .solarizedLight: return color(0x002B36)
        default: return ink
        }
    }
    var labelAccent: Color { theme == .solarizedLight ? foreground : accent }
    var lcdDigitColor: Color {
        switch theme {
        case .monokai: return color(0xAE81FF)
        case .desert: return color(0xFFA0A0)
        case .tokyoNight: return color(0xFF9E64)
        case .solarizedLight: return color(0x586E75)
        default: return accent
        }
    }
    var bodyColors: [Color] { theme == .charcoal ? [panel, ink] : [ink, ink] }
    var lcdGlass: [Color] {
        theme == .charcoal ? [
            Color(red: 0.64, green: 0.69, blue: 0.60),
            Color(red: 0.71, green: 0.75, blue: 0.66),
            Color(red: 0.63, green: 0.68, blue: 0.59)
        ] : [ink, ink]
    }
    var sliderTint: Color { theme == .charcoal ? Finish.lcd : accent }
    var dialTop: Color { theme == .charcoal ? Color(white: 0.29) : controlTop }
    var dialBottom: Color { theme == .charcoal ? Color(white: 0.15) : controlBottom }
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

private enum Finish {
    static let lcd = Color(red: 0.74, green: 0.81, blue: 0.66)
    static let orange = Color(red: 1.0, green: 0.49, blue: 0.25)
}

struct InstrumentButtonStyle: ButtonStyle {
    @Environment(\.instrumentTheme) private var theme
    private var palette: InstrumentPalette { theme.palette }
    var accent = false
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(accent ? palette.activeForeground : palette.foreground.opacity(theme == .charcoal ? 0.87 : 1))
            .background(
                LinearGradient(
                    colors: accent
                        ? [palette.accent, palette.accent]
                        : [palette.controlTop, palette.controlBottom],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(theme == .charcoal ? palette.border.opacity(configuration.isPressed ? 0.05 : 0.10) : palette.accent.opacity(configuration.isPressed ? 0.15 : 0.4), lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed || theme != .charcoal ? 0 : 0.3), radius: 2, y: 2)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

// Vector LCD digits keep the hardware's segment proportions at every scale.
private enum LCDSegments {
    // Segments: top, upper-right, lower-right, bottom, lower-left, upper-left, middle.
    static let numbers: [[Int]] = [
        [0,1,2,3,4,5], [1,2], [0,1,6,4,3], [0,1,6,2,3], [5,6,1,2],
        [0,5,6,2,3], [0,5,6,4,2,3], [0,1,2], [0,1,2,3,4,5,6], [0,1,2,3,5,6]
    ]
    // Every segment is 8 units thick with a consistent gap at each diagonal join.
    // Mirror the same geometry instead of drawing seven slightly different polygons.
    private static func horizontal(y: CGFloat) -> [CGPoint] {
        [CGPoint(x: 8, y: y), CGPoint(x: 32, y: y),
         CGPoint(x: 36, y: y + 4), CGPoint(x: 32, y: y + 8),
         CGPoint(x: 8, y: y + 8), CGPoint(x: 4, y: y + 4)]
    }
    private static let upperLeft: [CGPoint] = [
        CGPoint(x: 0, y: 9), CGPoint(x: 4, y: 5), CGPoint(x: 8, y: 9),
        CGPoint(x: 8, y: 33), CGPoint(x: 4, y: 37), CGPoint(x: 0, y: 33)
    ]
    static let polygons: [[CGPoint]] = [
        horizontal(y: 0),
        upperLeft.map { CGPoint(x: 40 - $0.x, y: $0.y) },
        upperLeft.map { CGPoint(x: 40 - $0.x, y: 76 - $0.y) },
        horizontal(y: 68),
        upperLeft.map { CGPoint(x: $0.x, y: 76 - $0.y) },
        upperLeft,
        horizontal(y: 34)
    ]
    static func path(digit: Int, origin: CGPoint, height: CGFloat) -> Path {
        var path = Path()
        let scale = height / 76
        for segment in numbers[min(9, max(0, digit))] {
            let points = polygons[segment].map { point in
                CGPoint(x: origin.x + point.x * scale,
                        y: origin.y + point.y * scale)
            }
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }
}

@MainActor
struct HardwareLCD: View {
    @ObservedObject var model: Metronome
    @State private var showingTempoEditor = false
    var compact = false
    var body: some View {
        // Read UI-isolated state here; Canvas and its local helpers only use snapshots.
        let theme = model.theme
        let palette = theme.palette
        let ink = theme == .charcoal ? Color(red: 0.08, green: 0.12, blue: 0.095) : palette.lcdDigitColor
        let bpm = model.bpm
        let subdivisions = model.subdivisions
        let beats = model.beats
        let sound = model.sound
        let playing = model.playing
        let currentBeat = model.currentBeat
        let beatTime = model.beatTime
        let beatNumber = model.beatNumber
        let inSilentBar = model.inSilentBar
        let compact = self.compact
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
            Canvas { context, size in
                let logical = compact ? CGSize(width: 140, height: 66) : CGSize(width: 280, height: 154)
                context.scaleBy(x: size.width / logical.width, y: size.height / logical.height)
                func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 10) {
                    context.draw(Text(text).font(.system(size: size, weight: .medium))
                        .foregroundColor(theme == .charcoal ? ink : palette.foreground), at: CGPoint(x: x, y: y), anchor: .topLeading)
                }
                func number(_ value: Int, places: Int, x: CGFloat, y: CGFloat, height: CGFloat) {
                    let chars = Array(String(value))
                    let advance = height * (46.0 / 76.0)
                    for index in 0..<places {
                        let source = index - (places - chars.count)
                        if source >= 0, source < chars.count, let digit = chars[source].wholeNumberValue {
                            context.fill(LCDSegments.path(digit: digit,
                                origin: CGPoint(x: x + CGFloat(index) * advance, y: y),
                                height: height), with: .color(ink))
                        }
                    }
                }
                if compact {
                    number(bpm, places: 3, x: 9, y: 7, height: 38)
                    label(inSilentBar ? "GAP" : "TEMPO", x: 87, y: 32, size: 7)
                } else {
                    number(bpm, places: 3, x: 65, y: 16, height: 64)
                    number(beats, places: 1, x: 235, y: 16, height: 64)
                    label("TEMPO", x: 9, y: 67, size: 11)
                    label("BEAT", x: 194, y: 67, size: 11)
                    label("VOICE", x: 47, y: 105, size: 10)
                    if inSilentBar { label("GAP", x: 196, y: 105, size: 10) }
                    number(sound + 1, places: 1, x: 101, y: 93, height: 29)
                    // Monochrome rhythm mark in the lower-right LCD corner.
                    let stems: [CGFloat] = subdivisions == 1 ? [259] : (subdivisions == 3 ? [246, 257, 268] : [248, 268])
                    for x in stems {
                        let head = Path(ellipseIn: CGRect(x: x - 7, y: 137, width: 8, height: 5))
                        context.fill(head, with: .color(ink))
                        var stem = Path()
                        stem.move(to: CGPoint(x: x, y: 139))
                        stem.addLine(to: CGPoint(x: x, y: 117))
                        context.stroke(stem, with: .color(ink), lineWidth: 1.7)
                    }
                    if subdivisions > 1, let first = stems.first, let last = stems.last {
                        context.fill(Path(CGRect(x: first, y: 116, width: last - first + 1, height: 3)), with: .color(ink))
                        if subdivisions == 4 {
                            context.fill(Path(CGRect(x: first, y: 122, width: last - first + 1, height: 3)), with: .color(ink))
                        }
                        if subdivisions == 3 { label("3", x: 254, y: 105, size: 8) }
                    }
                    // The pendulum changes direction on every audible pulse, including unaccented mode.
                    var symbol = Path()
                    symbol.move(to: CGPoint(x: 11, y: 115))
                    symbol.addLine(to: CGPoint(x: 15, y: 97))
                    symbol.addLine(to: CGPoint(x: 23, y: 97))
                    symbol.addLine(to: CGPoint(x: 27, y: 115))
                    symbol.closeSubpath()
                    let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - beatTime)
                    let phase = min(1, elapsed / (60 / Double(bpm)))
                    let direction: Double = beatNumber.isMultiple(of: 2) ? -1 : 1
                    let angle = playing && beatTime > 0
                        ? direction * cos(phase * .pi) * 0.5 : 0
                    symbol.move(to: CGPoint(x: 19, y: 112))
                    symbol.addLine(to: CGPoint(x: 19 + sin(angle) * 21, y: 112 - cos(angle) * 21))
                    context.stroke(symbol, with: .color(ink), lineWidth: 1.8)
                }
                let count = max(1, beats)
                // With no accent the beat index is always zero, so show each pulse
                // by briefly filling the marker instead of leaving it permanently filled.
                let timeSinceBeat = max(0, timeline.date.timeIntervalSinceReferenceDate - beatTime)
                let pulseDuration = min(0.14, (60 / Double(bpm)) * 0.45)
                let pulseVisible = playing && currentBeat >= 0
                    && timeSinceBeat < pulseDuration
                let width: CGFloat = compact ? 9 : 18
                let height: CGFloat = compact ? 9 : 19
                let spacing: CGFloat = compact ? 4 : 7
                let y: CGFloat = compact ? 52 : 127
                for index in 0..<count {
                    let x = CGFloat(index) * (width + spacing) + (compact ? 11 : 10)
                    var triangle = Path()
                    triangle.move(to: CGPoint(x: x, y: y))
                    triangle.addLine(to: CGPoint(x: x + width, y: y + height / 2))
                    triangle.addLine(to: CGPoint(x: x, y: y + height))
                    triangle.closeSubpath()
                    // Accented bars progress across markers; unaccented pulses flash.
                    let filled = beats == 0
                        ? pulseVisible : (currentBeat >= 0 && index <= currentBeat)
                    if filled {
                        context.fill(triangle, with: .color(ink))
                    }
                    context.stroke(triangle, with: .color(ink), lineWidth: compact ? 0.8 : 1.2)
                }
            }
            }
        .background(
            LinearGradient(colors: palette.lcdGlass, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: compact ? 5 : 9)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 9))
        .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 9)
            .strokeBorder(theme == .charcoal ? .black.opacity(0.65) : palette.fieldBorder, lineWidth: compact ? 1 : 2))
        .overlay {
            GeometryReader { geometry in
                let logical = compact ? CGSize(width: 140, height: 66) : CGSize(width: 280, height: 154)
                let target = compact ? CGRect(x: 5, y: 4, width: 78, height: 44)
                    : CGRect(x: 60, y: 10, width: 125, height: 76)
                Button {
                    showingTempoEditor = true
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: target.width * geometry.size.width / logical.width,
                       height: target.height * geometry.size.height / logical.height)
                .position(x: target.midX * geometry.size.width / logical.width,
                          y: target.midY * geometry.size.height / logical.height)
                .help("Click to enter tempo")
                .accessibilityLabel("Edit tempo")
                .accessibilityValue("\(bpm) beats per minute")
                .popover(isPresented: $showingTempoEditor, arrowEdge: .bottom) {
                    TempoEntry(bpm: model.bpm) { value in
                        model.bpm = value
                        showingTempoEditor = false
                    } onCancel: {
                        showingTempoEditor = false
                    }
                }
            }
        }
        .onChange(of: showingTempoEditor) { model.editingTempo = $0 }
        .onDisappear { model.editingTempo = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LCD")
        .accessibilityValue("\(bpm) beats per minute, \(beats == 0 ? "no accent" : "\(beats) beats per bar"), voice \(sound + 1), \(playing ? (inSilentBar ? "silent practice bar" : "playing") : "stopped")")
    }
}

@MainActor
struct TempoEntry: View {
    @State private var text: String
    @FocusState private var focused: Bool
    let onSet: (Int) -> Void
    let onCancel: () -> Void
    init(bpm: Int, onSet: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: String(bpm))
        self.onSet = onSet
        self.onCancel = onCancel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tempo").font(.headline)
            TextField("BPM", text: $text)
                .font(.system(size: 24, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { apply() }
                .accessibilityLabel("Tempo in beats per minute")
            Text("30–252 BPM").font(.caption).foregroundColor(.secondary)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Tempo.fromText(text) == nil)
            }
        }
        .padding(16).frame(width: 210)
        .onAppear { focused = true }
    }
    private func apply() {
        if let value = Tempo.fromText(text) { onSet(value) }
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
                    .foregroundColor(theme == .charcoal ? palette.muted : palette.labelAccent)
                HStack(spacing: 6) {
                    Text(selectedLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.foreground.opacity(0.92))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(theme == .charcoal ? palette.muted : palette.labelAccent)
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
    private var palette: InstrumentPalette { model.theme.palette }
    var showWidget: () -> Void
    @State private var dialStart: Int?
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("fdm-3").font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(-0.5).foregroundColor(model.theme == .charcoal ? palette.foreground.opacity(0.92) : palette.labelAccent)
                    Text("METRONOME").font(.system(size: 8, weight: .medium))
                        .tracking(1.8).foregroundColor(palette.muted)
                }
                Spacer()
                Button(action: showWidget) {
                    Label("Mini", systemImage: "pip")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).frame(height: 28)
                }
                .buttonStyle(InstrumentButtonStyle(radius: 8))
                .help("Switch to floating mini metronome (⇧⌘M)")
                .accessibilityLabel("Enter widget mode")
            }
            HardwareLCD(model: model).frame(height: 154)

            HStack(spacing: 0) {
                tempoDial
                Spacer(minLength: 36)
                VStack(spacing: 12) {
                    beatButton(delta: 1)
                    beatButton(delta: -1)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button { model.tap() } label: {
                    Text("TAP").font(.system(size: 11, weight: .semibold))
                        .tracking(1.2).frame(width: 76, height: 42)
                }.buttonStyle(InstrumentButtonStyle())
                Button { model.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.playing ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.playing ? "STOP" : "START")
                            .font(.system(size: 11, weight: .bold)).tracking(1.5)
                    }.frame(maxWidth: .infinity).frame(height: 42)
                }.buttonStyle(InstrumentButtonStyle(accent: model.playing))
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    SubdivisionSelector(value: $model.subdivisions)
                    gapSelector
                }
                HStack(spacing: 8) {
                    soundSelector
                    themeSelector
                }
                HStack(spacing: 10) {
                    Button { model.toggleMute() } label: {
                        Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                            .font(.system(size: 12))
                            .foregroundColor(model.volume == 0 ? palette.accent : palette.muted)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(model.volume == 0 ? "Unmute" : "Mute")
                    .accessibilityLabel(model.volume == 0 ? "Unmute" : "Mute")
                    Slider(value: $model.volume, in: 0...1)
                        .tint(palette.sliderTint).controlSize(.small).accessibilityLabel("Volume")
                }.padding(.horizontal, 4)
            }
        }
        .padding(18).frame(width: 320)
        .background(LinearGradient(colors: palette.bodyColors,
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(model.theme.colorScheme)
        .alert("Audio unavailable", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
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

    private var tempoDial: some View {
        ZStack {
            ForEach(0..<31, id: \.self) { index in
                Capsule().fill(palette.foreground.opacity(index % 5 == 0 ? 0.32 : 0.10))
                    .frame(width: 1.5, height: index % 5 == 0 ? 6 : 3)
                    .offset(y: -66)
                    .rotationEffect(.degrees(-135 + Double(index) * 9))
            }
            Circle()
                .fill(LinearGradient(colors: [palette.dialTop, palette.dialBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .overlay(Circle().strokeBorder(palette.border.opacity(0.14)))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
            Capsule().fill(palette.accent).frame(width: 4, height: 19)
                .offset(y: -42)
                .rotationEffect(.degrees(-135 + Double(model.bpm - 30) / 222 * 270))
        }
        .frame(width: 144, height: 144)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            if dialStart == nil { dialStart = model.bpm }
            model.bpm = Tempo.clamp((dialStart ?? model.bpm)
                + Int((value.translation.width - value.translation.height) / 3))
        }.onEnded { _ in dialStart = nil })
        .accessibilityElement().accessibilityLabel("Tempo dial")
        .accessibilityValue("\(model.bpm) beats per minute")
        .accessibilityAdjustableAction { direction in
            model.bpm += direction == .increment ? 1 : -1
        }
    }

    private func beatButton(delta: Int) -> some View {
        let atLimit = delta < 0 ? model.beats == 0 : model.beats == 9
        return Button {
            let index = Metronome.beatOptions.firstIndex(of: model.beats) ?? 0
            let next = min(Metronome.beatOptions.count - 1, max(0, index + delta))
            model.beats = Metronome.beatOptions[next]
        } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 15, weight: .regular))
                .rotationEffect(.degrees(delta > 0 ? 0 : 180))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(InstrumentButtonStyle(radius: 22))
        .disabled(atLimit)
        .opacity(atLimit ? 0.4 : 1)
        .help(delta < 0 ? "Decrease beats per bar (0 = no accent)" : "Increase beats per bar")
        .accessibilityLabel(delta < 0 ? "Decrease beats per bar" : "Increase beats per bar")
        .accessibilityValue(model.beats == 0 ? "No accent" : "\(model.beats) beats per bar")
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
        // Set the running Dock icon explicitly as well as embedding it for Finder.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
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
                  event.window === self.mainWindow || event.window === self.widget,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            else { return event }
            switch event.keyCode {
            case 49: // Space overrides focused button activation.
                if !event.isARepeat { self.model?.toggle() }
            case 123: // Left overrides a focused slider or picker.
                self.model?.bpm -= 10
            case 124: // Right
                self.model?.bpm += 10
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
                contentRect: NSRect(x: 0, y: 0, width: 196, height: 82),
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
            HardwareLCD(model: model, compact: true).frame(width: 140, height: 66)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Circle()
                    .fill(model.playing ? palette.accent : palette.foreground.opacity(0.18))
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
                .help("Return to fdm-3 (⇧⌘M)")
                .accessibilityLabel("Return to full fdm-3 window")
            }
        }
        .padding(.horizontal, 10).frame(width: 196, height: 82)
        .background(LinearGradient(colors: palette.bodyColors,
                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(palette.border.opacity(0.10)))
        .contextMenu {
            Button(model.playing ? "Stop" : "Start") { model.toggle() }
            Button("Tap Tempo") { model.tap() }
            Divider()
            Button("Show Full fdm-3") { showInstrument() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Quit fdm-3") { model.stop(); NSApp.terminate(nil) }
        }
        .environment(\.instrumentTheme, model.theme)
        .help("Drag to move. Click expand to return to fdm-3. Space starts or stops when focused.")
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
