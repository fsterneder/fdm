public enum GapCycle {
    public static let random = -1
    public static let fixedCounts = [1, 2, 4]
    public static let options = [0, 1, 2, 4, random]

    public static func label(for value: Int) -> String {
        if value == 0 { return "Off" }
        if value == random { return "Random" }
        return "After \(value) \(value == 1 ? "bar" : "bars")"
    }

    /// The chosen number of audible bars, then exactly one silent bar.
    /// No-accent mode uses four pulses per bar, without an audible accent.
    public static func isSilent(tick: Int, beats: Int, subdivisions: Int, audibleBars: Int) -> Bool {
        guard tick >= 0, fixedCounts.contains(audibleBars) else { return false }
        let pulsesPerBar = beats == 0 ? 4 : max(1, beats)
        let bar = tick / (pulsesPerBar * max(1, subdivisions))
        return bar % (audibleBars + 1) == audibleBars
    }
}

/// Consumed in chronological tick order by the audio scheduler.
/// Recreate on transport or pattern reset. Randomness is chosen once per cycle,
/// never separately for subdivisions or when the scheduler refills its queue.
public struct GapSequence {
    private var lastBar = -1
    private var nextSilentBar = 0
    private var needsPlan = true
    private var silent = false

    public init() {}

    public mutating func isSilent(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int,
        chooseAudibleBars: () -> Int = { GapCycle.fixedCounts.randomElement()! }
    ) -> Bool {
        guard audibleBars == GapCycle.random else {
            return GapCycle.isSilent(tick: tick, beats: beats, subdivisions: subdivisions, audibleBars: audibleBars)
        }
        guard tick >= 0 else { return false }
        let pulsesPerBar = beats == 0 ? 4 : max(1, beats)
        let bar = tick / (pulsesPerBar * max(1, subdivisions))
        if bar == lastBar { return silent }
        if needsPlan {
            let choice = chooseAudibleBars()
            let count = GapCycle.fixedCounts.contains(choice) ? choice : 1
            nextSilentBar = bar + count
            needsPlan = false
        }
        silent = bar == nextSilentBar
        if silent { needsPlan = true }
        lastBar = bar
        return silent
    }
}
