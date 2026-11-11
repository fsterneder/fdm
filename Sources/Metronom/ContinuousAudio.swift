import AVFoundation
import Darwin
import RealtimeAudio
import TempoCore

struct PlaybackConfiguration {
    var bpm: Int
    var beats: Int
    var subdivisions: Int
    var voice: Int
    var accent: Bool
    var gap: Int
    var gapBars: Int

    var raw: FDMConfig {
        FDMConfig(bpm: UInt32(bpm), beats: UInt32(beats), subdivisions: UInt32(subdivisions),
                  voice: UInt32(voice), accent: accent, gap: Int32(gap), gapBars: UInt32(gapBars))
    }
    init(bpm: Int, beats: Int, subdivisions: Int, voice: Int, accent: Bool, gap: Int, gapBars: Int) {
        self.bpm = bpm; self.beats = beats; self.subdivisions = subdivisions
        self.voice = voice; self.accent = accent; self.gap = gap; self.gapBars = gapBars
    }
    init(_ raw: FDMConfig) {
        self.init(bpm: Int(raw.bpm), beats: Int(raw.beats), subdivisions: Int(raw.subdivisions),
                  voice: Int(raw.voice), accent: raw.accent, gap: Int(raw.gap), gapBars: Int(raw.gapBars))
    }
}

struct RenderedBeat {
    let epoch: UInt64
    let hostTime: UInt64
    let number: UInt64
    let beat: Int
    let gapBarsRemaining: Int
    let cycleAudibleBars: Int
    let cycleBar: Int
    let configuration: PlaybackConfiguration
}

// The render callback captures only this immutable owner. All shared transport
// state lives behind C11 atomics; clip memory is immutable once rendering starts.
private final class AudioRenderState: @unchecked Sendable {
    let pointer: OpaquePointer
    init(sampleRate: Double) {
        pointer = FDMEngineCreate(sampleRate, UInt32.random(in: 1...UInt32.max))!
        for voice in ClickVoice.allCases {
            for kind in 0...2 {
                let samples = voice.samples(kind: kind, sampleRate: sampleRate)
                let loaded = samples.withUnsafeBufferPointer {
                    FDMEngineSetVoice(pointer, UInt32(voice.rawValue), UInt32(kind), $0.baseAddress, UInt32($0.count))
                }
                precondition(loaded, "Could not allocate click samples")
            }
        }
    }
    deinit { FDMEngineDestroy(pointer) }
}

@MainActor
final class ContinuousAudio {
    private let engine = AVAudioEngine()
    private let state: AudioRenderState
    private let source: AVAudioSourceNode

    init() {
        let rate = 48_000.0
        let renderState = AudioRenderState(sampleRate: rate)
        state = renderState
        let ticksPerFrame = Double(AVAudioTime.hostTime(forSeconds: 1)) / rate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        source = AVAudioSourceNode(format: format) { isSilence, timestamp, frames, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = buffers.first?.mData else { return noErr }
            let hostTime = timestamp.pointee.mFlags.contains(.hostTimeValid)
                ? timestamp.pointee.mHostTime : mach_absolute_time()
            isSilence.pointee = false
            FDMEngineRender(renderState.pointer, data.assumingMemoryBound(to: Float.self),
                            frames, hostTime, ticksPerFrame)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }
    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }
    func configure(_ configuration: PlaybackConfiguration) {
        FDMEngineConfigure(state.pointer, configuration.raw)
    }
    func start() throws -> UInt64 {
        // Engine is paused here, so the single consumer can discard prior runs.
        var old = FDMBeatEvent()
        while FDMEnginePoll(state.pointer, &old) {}
        let epoch = FDMEngineStart(state.pointer)
        do { try engine.start() }
        catch { FDMEngineStop(state.pointer); throw error }
        return epoch
    }
    func stop() {
        FDMEngineStop(state.pointer)
        engine.pause()
    }
    func poll() -> RenderedBeat? {
        var event = FDMBeatEvent()
        guard FDMEnginePoll(state.pointer, &event) else { return nil }
        return RenderedBeat(epoch: event.epoch, hostTime: event.hostTime, number: event.number,
                            beat: Int(event.beat), gapBarsRemaining: Int(event.gapBarsRemaining),
                            cycleAudibleBars: Int(event.cycleAudibleBars), cycleBar: Int(event.cycleBar),
                            configuration: PlaybackConfiguration(event.config))
    }
}

