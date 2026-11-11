import Foundation

/// Accumulate small mouse movements and discard overshoot at the tempo limits.
public struct TempoScrubber {
    public private(set) var bpm: Int
    private var remainder: Double = 0
    public init(bpm: Int) { self.bpm = Tempo.clamp(bpm) }

    public mutating func move(upwardPoints: Double) -> Int {
        remainder += upwardPoints
        let steps = Int(remainder / 3)
        guard steps != 0 else { return bpm }
        remainder -= Double(steps) * 3
        let requested = bpm + steps
        bpm = Tempo.clamp(requested)
        if requested != bpm { remainder = 0 }
        return bpm
    }
}
