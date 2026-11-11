import SwiftUI
import AppKit
import AVFoundation
import Darwin
import TempoCore

@main
@MainActor
struct MetronomApp: App {
    @StateObject private var model = Metronome()
    @StateObject private var windows = WindowModes()
    var body: some Scene {
        WindowGroup("fdm-3") {
            InstrumentView(model: model, showWidget: { windows.showWidget() })
                .background(WindowBridge(windows: windows, model: model))
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Start / Stop") { model.toggle() }.keyboardShortcut(.space, modifiers: [])
                Button("Tap Tempo") { model.tap() }.keyboardShortcut("t", modifiers: [])
                Button("Faster") { model.bpm += 1 }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Slower") { model.bpm -= 1 }.keyboardShortcut(.downArrow, modifiers: [])
            }
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Widget Mode") { windows.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
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
        sound = min(2, max(0, defaults.integer(forKey: "sound")))
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
            nextFrame = 0; tick = 0; currentBeat = -1
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
        player.stop(); playing = false; currentBeat = -1
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
                        self.currentBeat = beat
                    }
                }
            }
            nextFrame += Tempo.frames(bpm: bpm, subdivisions: subdivisions, sampleRate: format.sampleRate)
            tick += 1
        }
    }
    private func makeClick(kind: Int) -> AVAudioPCMBuffer {
        let count = AVAudioFrameCount(0.025 * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        let frequency: Double = [1800, 1100, 750][kind] * [1.0, 0.62, 1.5][sound]
        let gain: Double = [0.8, 0.55, 0.26][kind]
        for index in 0..<Int(count) {
            let t = Double(index) / format.sampleRate
            let attack = min(1, t / 0.0008)
            let decay = exp(-t * (sound == 1 ? 230 : 160))
            let fundamental = sin(2 * .pi * frequency * t)
            let overtone = sound == 1 ? 0.45 * sin(2 * .pi * frequency * 2.7 * t) : 0
            buffer.floatChannelData![0][index] = Float((fundamental + overtone) * attack * decay * gain)
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
}

struct InstrumentButtonStyle: ButtonStyle {
    var accent = false
    var radius: CGFloat = 10
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(accent ? Finish.ink : Color(white: 0.87))
            .background(
                LinearGradient(
                    colors: accent
                        ? [Finish.orange, Color(red: 0.88, green: 0.35, blue: 0.16)]
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

struct BeatStrip: View {
    let beats: Int
    let current: Int
    var dark = false
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            ForEach(0..<max(1, beats), id: \.self) { index in
                Capsule()
                    .fill(index == current
                        ? (dark ? Color.black.opacity(0.78) : Finish.orange)
                        : (dark ? Color.black.opacity(0.14) : Color.white.opacity(0.13)))
                    .frame(width: compact ? 10 : 16, height: compact ? 4 : 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beats")
        .accessibilityValue(current < 0 ? "Stopped" : "Beat \(current + 1) of \(max(1, beats))")
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TEMPO").font(.system(size: 9, weight: .semibold)).tracking(2)
                    Spacer()
                    Circle().fill(.black.opacity(model.playing ? 0.75 : 0.16))
                        .frame(width: 5, height: 5)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(String(model.bpm))
                        .font(.system(size: 66, weight: .regular, design: .monospaced))
                        .monospacedDigit().tracking(-4)
                        .accessibilityLabel("Tempo")
                        .accessibilityValue("\(model.bpm) beats per minute")
                    Spacer(minLength: 8)
                    Text("BPM").font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                BeatStrip(beats: model.beats, current: model.currentBeat, dark: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
            .foregroundColor(.black.opacity(0.72))
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Finish.lcd, Color(red: 0.66, green: 0.74, blue: 0.58)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.6), lineWidth: 2))

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
                }.buttonStyle(InstrumentButtonStyle(accent: true))
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    SettingMenu(title: "BEATS", value: $model.beats, values: Array(0...9))
                    SettingMenu(title: "DIVISION", value: $model.subdivisions, values: Array(1...4))
                }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Button { model.sound = index } label: {
                            Text(["Click", "Wood", "Bright"][index])
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(model.sound == index ? .white.opacity(0.92) : Finish.muted)
                                .frame(maxWidth: .infinity).frame(height: 29)
                                .background(model.sound == index ? Color.white.opacity(0.10) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(3).background(Finish.ink.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 10) {
                    Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 12)).foregroundColor(Finish.muted).frame(width: 18)
                    Slider(value: $model.volume, in: 0...1)
                        .tint(Finish.lcd).controlSize(.small).accessibilityLabel("Volume")
                }.padding(.horizontal, 4)
            }
            Text("SPACE  play / stop     T  tap     ↑ ↓  tempo")
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

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 40, height: 36)
        }
        .buttonStyle(InstrumentButtonStyle(radius: 18))
        .accessibilityLabel(label)
    }
}


// Intercept Space before focused buttons consume it as their activation key.
// This monitor is local to this app and does not require accessibility permission.
@MainActor
final class WindowModes: ObservableObject {
    private weak var mainWindow: NSWindow?
    private weak var model: Metronome?
    private var widget: TempoPanel?
    private var keyMonitor: Any?
    private var closeObserver: NSObjectProtocol?

    func attach(window: NSWindow, model: Metronome) {
        guard mainWindow !== window else { return }
        mainWindow = window
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
                self?.model?.stop()
                self?.widget?.orderOut(nil)
            }
        }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.mainWindow || event.window === self.widget,
                  event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            else { return event }
            if !event.isARepeat { self.model?.toggle() }
            return nil
        }
    }

    func toggle() {
        if widget?.isVisible == true { showInstrument() } else { showWidget() }
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
        mainWindow.orderOut(nil)
        widget?.makeKeyAndOrderFront(nil)
    }

    func showInstrument() {
        widget?.orderOut(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(String(model.bpm))
                        .font(.system(size: 38, weight: .regular, design: .monospaced))
                        .monospacedDigit().tracking(-2)
                        .foregroundColor(Finish.lcd)
                        .accessibilityLabel("Tempo")
                        .accessibilityValue("\(model.bpm) beats per minute")
                        .accessibilityAdjustableAction { direction in
                            model.bpm += direction == .increment ? 1 : -1
                        }
                    Text("BPM").font(.system(size: 8, weight: .medium))
                        .foregroundColor(Finish.muted)
                }
                BeatStrip(beats: model.beats, current: model.currentBeat, compact: true)
            }
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
        .padding(.horizontal, 14).frame(width: 196, height: 82)
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
