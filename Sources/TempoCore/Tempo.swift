import Foundation

public enum Tempo {
    public static func clamp(_ value: Int) -> Int { min(252, max(30, value)) }
    /// Allow empty text during editing; only up to three ASCII digits otherwise.
    public static func isValidDraft(_ text: String) -> Bool {
        text.utf8.count <= 3 && text.utf8.allSatisfy { (48...57).contains($0) }
    }
    public static func fromText(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return clamp(value)
    }
    public static func frames(bpm: Int, subdivisions: Int, sampleRate: Double) -> Double {
        sampleRate * 60 / Double(clamp(bpm)) / Double(max(1, subdivisions))
    }
}

public struct TapTempo {
    private var taps: [TimeInterval] = []
    public init() {}
    public mutating func tap(at time: TimeInterval) -> Int? {
        if let last = taps.last, time - last > 2.1 || time <= last { taps = [] }
        taps.append(time)
        taps = Array(taps.suffix(6))
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        return Tempo.clamp(Int((60 * Double(taps.count - 1) / (last - first)).rounded()))
    }
}
