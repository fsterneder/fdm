public enum GapCycle {
    public static let random = -1
    public static let fixedCounts = [1, 2, 4]
    public static let options = [0, 1, 2, 4, random]
    public static let lengthOptions = Array(1...8)

    public static func label(for value: Int) -> String {
        if value == 0 { return "Off" }
        if value == random { return "Random" }
        return "After \(value) \(value == 1 ? "bar" : "bars")"
    }
    private static func meter(_ beats: Int) -> Int { beats == 0 ? 4 : max(1, beats) }
    public static func restoredLength(savedBars: Int?, legacyBeats: Int?, beatsPerBar: Int) -> Int {
        if let savedBars { return min(8, max(1, savedBars)) }
        guard let legacyBeats else { return 1 }
        let beats = max(1, legacyBeats)
        let bars = (beats - 1) / max(1, beatsPerBar) + 1
        return min(8, max(1, bars))
    }
    public static func isSilent(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBars: Int = 1
    ) -> Bool {
        silentBarsRemaining(tick: tick, beats: beats, subdivisions: subdivisions,
                            audibleBars: audibleBars, silentBars: silentBars) > 0
    }
    public static func silentBarsRemaining(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBars: Int = 1
    ) -> Int {
        guard tick >= 0, fixedCounts.contains(audibleBars) else { return 0 }
        let length = min(8, max(1, silentBars))
        let bar = tick / (meter(beats) * max(1, subdivisions))
        let position = bar % (audibleBars + length)
        return position >= audibleBars ? audibleBars + length - position : 0
    }
}

/// A random audible run is selected once per complete audible/silent cycle.
/// All transitions occur on bar boundaries, including subdivisions.
public struct GapSequence {
    private var cycleEndBar = 0
    private var silentStartBar = 0
    private var lastBar = -1
    public private(set) var silentBarsRemaining = 0

    public init() {}
    public mutating func isSilent(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBars: Int = 1,
        chooseAudibleBars: () -> Int = { GapCycle.fixedCounts.randomElement()! }
    ) -> Bool {
        guard audibleBars == GapCycle.random else {
            silentBarsRemaining = GapCycle.silentBarsRemaining(
                tick: tick, beats: beats, subdivisions: subdivisions,
                audibleBars: audibleBars, silentBars: silentBars)
            return silentBarsRemaining > 0
        }
        guard tick >= 0 else { silentBarsRemaining = 0; return false }
        let meter = beats == 0 ? 4 : max(1, beats)
        let bar = tick / (meter * max(1, subdivisions))
        if bar == lastBar { return silentBarsRemaining > 0 }
        let length = min(8, max(1, silentBars))
        while bar >= cycleEndBar {
            let choice = chooseAudibleBars()
            let count = GapCycle.fixedCounts.contains(choice) ? choice : 1
            silentStartBar = cycleEndBar + count
            cycleEndBar = silentStartBar + length
        }
        silentBarsRemaining = bar >= silentStartBar ? cycleEndBar - bar : 0
        lastBar = bar
        return silentBarsRemaining > 0
    }
}
