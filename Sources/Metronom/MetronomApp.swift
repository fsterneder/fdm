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
        }
        .windowResizability(.contentSize)
        .commands {
            // Keep one instrument window; widget mode uses a companion panel.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Start / Stop") { model.toggle() }.keyboardShortcut(.space, modifiers: [])
                Button("Tap Tempo") { model.tap() }.keyboardShortcut("t", modifiers: [])
                Button("Faster") { model.bpm += 1 }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Slower") { model.bpm -= 1 }.keyboardShortcut(.downArrow, modifiers: [])
                Button("Faster by 10 BPM") { model.bpm += 10 }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Slower by 10 BPM") { model.bpm -= 10 }.keyboardShortcut(.leftArrow, modifiers: [])
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
    @Published var bpm: Int { didSet {
        let bounded = Tempo.clamp(bpm)
        if bpm != bounded { bpm = bounded; return }
        UserDefaults.standard.set(bpm, forKey: "bpm"); restart()
    } }
    @Published var beats: Int { didSet { UserDefaults.standard.set(beats, forKey: "beats"); restart() } }
    @Published var subdivisions: Int { didSet { UserDefaults.standard.set(subdivisions, forKey: "subdivisions"); restart() } }
    @Published var sound: Int { didSet { UserDefaults.standard.set(sound, forKey: "sound"); restart() } }
    @Published var volume: Double { didSet {
        player.volume = Float(volume)
        UserDefaults.standard.set(volume, forKey: "volume")
    } }
    @Published private(set) var playing = false
    @Published private(set) var currentBeat = -1
    @Published private(set) var beatTime: TimeInterval = 0
    @Published private(set) var beatNumber = 0
    @Published var error: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var timer: Timer?
    private var nextFrame: Double = 0
    private var tick = 0
    private var generation = UUID()
    private var tapper = TapTempo()
    private var buffers: [AVAudioPCMBuffer] = []
    private var activity: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["bpm": 120, "beats": 4, "subdivisions": 1, "sound": 0, "volume": 0.65])
        bpm = Tempo.clamp(defaults.integer(forKey: "bpm"))
        beats = min(9, max(0, defaults.integer(forKey: "beats")))
        subdivisions = min(4, max(1, defaults.integer(forKey: "subdivisions")))
        sound = min(ClickVoice.allCases.count - 1, max(0, defaults.integer(forKey: "sound")))
        volume = min(1, max(0, defaults.double(forKey: "volume")))
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.volume = Float(volume)
    }
    func toggle() { playing ? stop() : start() }
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
            playing = true
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
        player.stop(); playing = false; currentBeat = -1; beatTime = 0
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
            let frame = AVAudioFramePosition(nextFrame.rounded())
            player.scheduleBuffer(buffers[kind], at: AVAudioTime(sampleTime: frame, atRate: format.sampleRate), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                if mainBeat {
                    Task { @MainActor in
                        guard let self, self.playing, self.generation == run else { return }
                        self.beatTime = Date.timeIntervalSinceReferenceDate
                        self.beatNumber &+= 1
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

private enum Finish {
    static let ink = Color(red: 0.055, green: 0.063, blue: 0.067)
    static let panel = Color(red: 0.105, green: 0.117, blue: 0.122)
    static let muted = Color(red: 0.52, green: 0.56, blue: 0.56)
    static let lcd = Color(red: 0.74, green: 0.81, blue: 0.66)
    static let orange = Color(red: 1.0, green: 0.49, blue: 0.25)
    static let transportRed = Color(red: 0.92, green: 0.20, blue: 0.24)
}

struct InstrumentButtonStyle: ButtonStyle {
    var accent = false
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(accent ? Color.white : Color(white: 0.87))
            .background(
                LinearGradient(
                    colors: accent
                        ? [Finish.transportRed, Color(red: 0.66, green: 0.08, blue: 0.12)]
                        : [Color(white: 0.23), Color(white: 0.16)],
                    startPoint: .top, endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: radius)
            )
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(.white.opacity(configuration.isPressed ? 0.05 : 0.10), lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.3), radius: 2, y: 2)
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
    var compact = false
    private let ink = Color(red: 0.08, green: 0.12, blue: 0.095)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.playing || compact)) { timeline in
            Canvas { context, size in
                let logical = compact ? CGSize(width: 140, height: 66) : CGSize(width: 280, height: 154)
                context.scaleBy(x: size.width / logical.width, y: size.height / logical.height)
                func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 10) {
                    context.draw(Text(text).font(.system(size: size, weight: .medium))
                        .foregroundColor(ink), at: CGPoint(x: x, y: y), anchor: .topLeading)
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
                    number(model.bpm, places: 3, x: 9, y: 7, height: 38)
                    label("TEMPO", x: 87, y: 32, size: 7)
                } else {
                    number(model.bpm, places: 3, x: 65, y: 16, height: 64)
                    number(model.beats, places: 1, x: 235, y: 16, height: 64)
                    label("TEMPO", x: 9, y: 67, size: 11)
                    label("BEAT", x: 194, y: 67, size: 11)
                    label("VOICE", x: 47, y: 105, size: 10)
                    number(model.sound + 1, places: 1, x: 101, y: 93, height: 29)
                    // The pendulum changes direction on every audible pulse, including unaccented mode.
                    var symbol = Path()
                    symbol.move(to: CGPoint(x: 11, y: 115))
                    symbol.addLine(to: CGPoint(x: 15, y: 97))
                    symbol.addLine(to: CGPoint(x: 23, y: 97))
                    symbol.addLine(to: CGPoint(x: 27, y: 115))
                    symbol.closeSubpath()
                    let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - model.beatTime)
                    let phase = min(1, elapsed / (60 / Double(model.bpm)))
                    let direction: Double = model.beatNumber.isMultiple(of: 2) ? -1 : 1
                    let angle = model.playing && model.beatTime > 0
                        ? direction * cos(phase * .pi) * 0.5 : 0
                    symbol.move(to: CGPoint(x: 19, y: 112))
                    symbol.addLine(to: CGPoint(x: 19 + sin(angle) * 21, y: 112 - cos(angle) * 21))
                    context.stroke(symbol, with: .color(ink), lineWidth: 1.8)
                }
                let count = max(1, model.beats)
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
                    // The hardware fills the markers up to the current beat.
                    if model.currentBeat >= 0 && index <= model.currentBeat {
                        context.fill(triangle, with: .color(ink))
                    }
                    context.stroke(triangle, with: .color(ink), lineWidth: compact ? 0.8 : 1.2)
                }
            }
            }
        .background(
            LinearGradient(colors: [
                Color(red: 0.64, green: 0.69, blue: 0.60),
                Color(red: 0.71, green: 0.75, blue: 0.66),
                Color(red: 0.63, green: 0.68, blue: 0.59)
            ], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: compact ? 5 : 9)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 5 : 9))
        .overlay(RoundedRectangle(cornerRadius: compact ? 5 : 9)
            .strokeBorder(.black.opacity(0.65), lineWidth: compact ? 1 : 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LCD")
        .accessibilityValue("\(model.bpm) beats per minute, \(model.beats == 0 ? "no accent" : "\(model.beats) beats per bar"), voice \(model.sound + 1), \(model.playing ? "playing" : "stopped")")
    }
}

struct SettingMenu: View {
    let title: String
    @Binding var value: Int
    let values: [Int]
    var body: some View {
        Menu {
            ForEach(values, id: \.self) { number in
                Button {
                    value = number
                } label: {
                    if value == number {
                        Label(number == 0 ? "No accent" : "\(number)", systemImage: "checkmark")
                    } else {
                        Text(number == 0 ? "No accent" : "\(number)")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 9, weight: .semibold)).tracking(1)
                    .foregroundColor(Finish.muted)
                Spacer(minLength: 0)
                Text(value == 0 ? "—" : "\(value)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.86))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold)).foregroundColor(Finish.muted)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Finish.ink.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(title)
        .accessibilityValue(value == 0 ? "No accent" : "\(value)")
    }
}

@MainActor
struct InstrumentView: View {
    @ObservedObject var model: Metronome
    var showWidget: () -> Void
    @State private var dialStart: Int?
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("fdm-3").font(.system(size: 18, weight: .bold, design: .rounded))
                        .tracking(-0.5).foregroundColor(.white.opacity(0.92))
                    Text("METRONOME").font(.system(size: 8, weight: .medium))
                        .tracking(1.8).foregroundColor(Finish.muted)
                }
                Spacer()
                Button(action: showWidget) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(InstrumentButtonStyle(radius: 8))
                .help("Widget mode (⇧⌘M)")
                .accessibilityLabel("Enter widget mode")
            }
            HardwareLCD(model: model).frame(height: 154)

            HStack(spacing: 24) {
                stepButton("minus", label: "Decrease tempo") { model.bpm -= 1 }
                ZStack {
                    ForEach(0..<31, id: \.self) { index in
                        Capsule().fill(Color.white.opacity(index % 5 == 0 ? 0.32 : 0.10))
                            .frame(width: 1.5, height: index % 5 == 0 ? 5 : 3)
                            .offset(y: -41)
                            .rotationEffect(.degrees(-135 + Double(index) * 9))
                    }
                    Circle().fill(LinearGradient(colors: [Color(white: 0.29), Color(white: 0.15)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                        .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 3)
                    Capsule().fill(Finish.orange).frame(width: 3, height: 12)
                        .offset(y: -23)
                        .rotationEffect(.degrees(-135 + Double(model.bpm - 30) / 222 * 270))
                }
                .frame(width: 88, height: 88).contentShape(Circle())
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
                stepButton("plus", label: "Increase tempo") { model.bpm += 1 }
            }.frame(maxWidth: .infinity)

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
                    SettingMenu(title: "BEATS", value: $model.beats, values: Array(0...9))
                    SettingMenu(title: "DIVISION", value: $model.subdivisions, values: Array(1...4))
                }
                soundSelector
                HStack(spacing: 10) {
                    Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 12)).foregroundColor(Finish.muted).frame(width: 18)
                    Slider(value: $model.volume, in: 0...1)
                        .tint(Finish.lcd).controlSize(.small).accessibilityLabel("Volume")
                }.padding(.horizontal, 4)
            }
            Text("SPACE play/stop · T tap · ↑↓ ±1 · ←→ ±10")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(Finish.muted.opacity(0.75))
        }
        .padding(18).frame(width: 320)
        .background(LinearGradient(colors: [Finish.panel, Finish.ink],
                                  startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .alert("Audio unavailable", isPresented: Binding(
            get: { model.error != nil }, set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var soundSelector: some View {
        Menu {
            Picker("Sound", selection: $model.sound) {
                ForEach(ClickVoice.allCases, id: \.rawValue) { voice in
                    Text(voice.name).tag(voice.rawValue)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("SOUND")
                    .font(.system(size: 9, weight: .semibold)).tracking(1)
                    .foregroundColor(Finish.muted)
                Spacer(minLength: 0)
                Text((ClickVoice(rawValue: model.sound) ?? .click).name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Finish.muted)
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Finish.ink.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Sound")
        .accessibilityValue((ClickVoice(rawValue: model.sound) ?? .click).name)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 40, height: 36)
        }
        .buttonStyle(InstrumentButtonStyle(radius: 18))
        .accessibilityLabel(label)
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
            guard let self,
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
    var showInstrument: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            HardwareLCD(model: model, compact: true).frame(width: 140, height: 66)
            Spacer(minLength: 0)
            Button(action: showInstrument) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(InstrumentButtonStyle(radius: 8))
            .help("Return to fdm-3 (⇧⌘M)")
            .accessibilityLabel("Return to full fdm-3 window")
        }
        .padding(.horizontal, 10).frame(width: 196, height: 82)
        .background(LinearGradient(colors: [Finish.panel, Finish.ink],
                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.10)))
        .contextMenu {
            Button(model.playing ? "Stop" : "Start") { model.toggle() }
            Button("Tap Tempo") { model.tap() }
            Divider()
            Button("Show Full fdm-3") { showInstrument() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Quit fdm-3") { model.stop(); NSApp.terminate(nil) }
        }
        .help("Drag to move. Click expand to return to fdm-3. Space starts or stops when focused.")
        .preferredColorScheme(.dark)
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
