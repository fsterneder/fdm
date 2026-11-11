import Foundation

public enum ClickVoice: Int, CaseIterable {
    // Keep existing values stable so saved sound preferences remain valid.
    case click = 0, wood, bright, clave, softPulse

    public var name: String {
        switch self {
        case .click: return "Click"
        case .wood: return "Wood"
        case .bright: return "Bright"
        case .clave: return "Clave"
        case .softPulse: return "Soft Pulse"
        }
    }

    public func samples(kind: Int, sampleRate: Double) -> [Float] {
        guard sampleRate.isFinite, sampleRate > 0 else { return [] }
        let kind = min(2, max(0, kind)) // first beat, regular beat, subdivision
        // At 252 BPM with four subdivisions the spacing is 59.5 ms.
        // Keep even the soft pulse shorter than that to avoid overlapping buffers.
        let duration: Double = self == .softPulse ? 0.050 : (self == .clave ? 0.040 : 0.025)
        let count = max(1, Int((duration * sampleRate).rounded()))
        let gain: Double = [0.8, 0.55, 0.26][kind]
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let wave: Double
            switch self {
            case .click, .wood, .bright:
                let ratio: Double = self == .wood ? 0.62 : (self == .bright ? 1.5 : 1)
                let frequency = [1800.0, 1100.0, 750.0][kind] * ratio
                let attack = min(1, t / 0.0008)
                let decay = exp(-t * (self == .wood ? 230 : 160))
                let fundamental = sin(2 * .pi * frequency * t)
                let overtone = self == .wood ? 0.45 * sin(2 * .pi * frequency * 2.7 * t) : 0
                wave = (fundamental + overtone) * attack * decay
            case .clave:
                let frequency = [2450.0, 1850.0, 1500.0][kind]
                let attack = min(1, t / 0.00025)
                let body = 0.72 * sin(2 * .pi * frequency * t) * exp(-180 * t)
                let resonance = 0.24 * sin(2 * .pi * frequency * 1.47 * t) * exp(-260 * t)
                let strike = 0.04 * sin(2 * .pi * frequency * 2.1 * t) * exp(-700 * t)
                let release = min(1, Double(count - 1 - index) / (sampleRate * 0.004))
                wave = (body + resonance + strike) * attack * release
            case .softPulse:
                let frequency = [440.0, 330.0, 260.0][kind]
                let attackProgress = min(1, t / 0.004)
                let attack = 0.5 - 0.5 * cos(.pi * attackProgress)
                let releaseProgress = min(1, Double(count - 1 - index) / (sampleRate * 0.008))
                let release = 0.5 - 0.5 * cos(.pi * releaseProgress)
                wave = sin(2 * .pi * frequency * t) * attack * exp(-70 * t) * release
            }
            return Float(wave * gain)
        }
    }
}
