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
        WindowGroup("Metronom") {
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

@MainActor
struct InstrumentView: View {
    @ObservedObject var model: Metronome
    var showWidget: () -> Void
    @State private var dialStart: Int?
    private let lcd = Color(red: 0.70, green: 0.77, blue: 0.61)
    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("METRONOM").font(.system(size: 17, weight: .black, design: .rounded)).tracking(4)
                Spacer()
                Button(action: showWidget) {
                    Image(systemName: "pip.enter")
                }
                .help("Widget mode (⇧⌘M)")
                .accessibilityLabel("Enter widget mode")
                Circle().fill(model.playing ? Color.orange : Color.white.opacity(0.15)).frame(width: 8, height: 8)
            }
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(model.bpm)).font(.system(size: 86, weight: .medium, design: .monospaced)).monospacedDigit()
                    Text("BPM").font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                HStack(spacing: 10) {
                    ForEach(0..<max(1, model.beats), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(model.currentBeat == index ? 0.85 : 0.16))
                            .frame(width: 18, height: 7)
                    }
                }.frame(height: 12)
            }
            .foregroundColor(.black.opacity(0.85))
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(lcd.gradient, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 4))
            HStack(spacing: 28) {
                Button { model.bpm -= 1 } label: { Image(systemName: "minus").frame(width: 28, height: 34) }
                    .accessibilityLabel("Decrease tempo")
                ZStack {
                    Circle().fill(.black.opacity(0.4)).frame(width: 126, height: 126)
                    Circle().fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 112, height: 112).overlay(Circle().stroke(Color(white: 0.4), lineWidth: 1))
                    Capsule().fill(.orange).frame(width: 4, height: 22).offset(y: -37)
                        .rotationEffect(.degrees(-135 + Double(model.bpm - 30) / 222 * 270))
                }
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if dialStart == nil { dialStart = model.bpm }
                    model.bpm = Tempo.clamp((dialStart ?? model.bpm) + Int((value.translation.width - value.translation.height) / 3))
                }.onEnded { _ in dialStart = nil })
                .accessibilityElement().accessibilityLabel("Tempo").accessibilityValue("\(model.bpm) beats per minute")
                .accessibilityAdjustableAction { direction in model.bpm += direction == .increment ? 1 : -1 }
                Button { model.bpm += 1 } label: { Image(systemName: "plus").frame(width: 28, height: 34) }
                    .accessibilityLabel("Increase tempo")
            }
            HStack(spacing: 12) {
                Button("TAP") { model.tap() }.frame(maxWidth: .infinity)
                Button(model.playing ? "STOP" : "START") { model.toggle() }
                    .tint(.orange).frame(maxWidth: .infinity)
            }.controlSize(.large).font(.system(size: 13, weight: .bold, design: .monospaced))
            Divider().overlay(.white.opacity(0.15))
            HStack {
                Picker("Beats", selection: $model.beats) {
                    Text("No accent").tag(0)
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Division", selection: $model.subdivisions) {
                    Text("1").tag(1); Text("2").tag(2); Text("3").tag(3); Text("4").tag(4)
                }
            }
            Picker("Sound", selection: $model.sound) {
                Text("Click").tag(0); Text("Wood").tag(1); Text("Bright").tag(2)
            }.pickerStyle(.segmented)
            HStack {
                Image(systemName: "speaker.wave.2.fill").foregroundColor(.gray)
                Slider(value: $model.volume, in: 0...1).accessibilityLabel("Volume")
            }
            Text("SPACE  start / stop     T  tap     ↑ ↓  tempo")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            VStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(.black.opacity(0.35)).frame(height: 3) }
            }.padding(.horizontal, 45).padding(.top, 3)
        }
        .buttonStyle(.bordered)
        .padding(28).frame(width: 390)
        .background(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .preferredColorScheme(.dark)
        .alert("Audio unavailable", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
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
                contentRect: NSRect(x: 0, y: 0, width: 160, height: 88),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.title = "Metronom Tempo"
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
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
        Text(String(model.bpm))
            .font(.system(size: 52, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(Color(red: 0.70, green: 0.77, blue: 0.61))
            .frame(width: 160, height: 88)
            .background(Color(white: 0.10))
            .contentShape(Rectangle())
            .contextMenu {
                Button(model.playing ? "Stop" : "Start") { model.toggle() }
                Button("Tap Tempo") { model.tap() }
                Divider()
                Button("Show Full Metronome") { showInstrument() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .help("Drag to move. Right-click for controls or to return to the full metronome. Space starts or stops when focused.")
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(model.bpm) beats per minute")
            .accessibilityAdjustableAction { direction in
                model.bpm += direction == .increment ? 1 : -1
            }
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
