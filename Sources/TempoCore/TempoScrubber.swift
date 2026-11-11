import Foundation

/// Drag a bounded sequence without accumulating overshoot at its ends.
public struct ValueScrubber {
    public private(set) var value: Int
    private let bounds: ClosedRange<Int>
    private let pointsPerStep: Double
    private var remainder: Double = 0
    public init(value: Int, bounds: ClosedRange<Int>, pointsPerStep: Double) {
        precondition(pointsPerStep > 0)
        self.bounds = bounds
        self.pointsPerStep = pointsPerStep
        self.value = min(bounds.upperBound, max(bounds.lowerBound, value))
    }
    public mutating func move(upwardPoints: Double) -> Int {
        remainder += upwardPoints
        let steps = Int(remainder / pointsPerStep)
        guard steps != 0 else { return value }
        remainder -= Double(steps) * pointsPerStep
        let requested = value + steps
        value = min(bounds.upperBound, max(bounds.lowerBound, requested))
        if requested != value { remainder = 0 }
        return value
    }
}

/// Tempo uses the same drag behavior, with one BPM per three vertical points.
public struct TempoScrubber {
    private var state: ValueScrubber
    public var bpm: Int { state.value }
    public init(bpm: Int) { state = ValueScrubber(value: bpm, bounds: 30...252, pointsPerStep: 3) }
    public mutating func move(upwardPoints: Double) -> Int { state.move(upwardPoints: upwardPoints) }
}
