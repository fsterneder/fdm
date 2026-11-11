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
    static func beatsPerBar(_ beats: Int) -> Int { beats == 0 ? 4 : max(1, beats) }
    static func length(_ silentBeats: Int?, meter: Int) -> Int {
        // Omitted length preserves the old one-silent-bar API.
        silentBeats.map { min(8, max(1, $0)) } ?? meter
    }

    /// Audible bars' worth of beats followed by a fixed number of silent beats.
    /// The underlying beat/subdivision grid never stops or resets for silence.
    public static func isSilent(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBeats: Int? = nil
    ) -> Bool {
        silentBeatsRemaining(tick: tick, beats: beats, subdivisions: subdivisions,
                            audibleBars: audibleBars, silentBeats: silentBeats) > 0
    }
    public static func silentBeatsRemaining(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBeats: Int? = nil
    ) -> Int {
        guard tick >= 0, fixedCounts.contains(audibleBars) else { return 0 }
        let meter = beatsPerBar(beats)
        let audible = audibleBars * meter
        let silent = length(silentBeats, meter: meter)
        let beat = tick / max(1, subdivisions)
        let position = beat % (audible + silent)
        return position >= audible ? audible + silent - position : 0
    }
}

/// Consumed chronologically by the sample scheduler. Recreate on pattern/reset.
/// Randomness is chosen once per complete audible/silent cycle.
public struct GapSequence {
    private var cycleEndBeat = 0
    private var silentStartBeat = 0
    private var lastBeat = -1
    public private(set) var silentBeatsRemaining = 0

    public init() {}
    public mutating func isSilent(
        tick: Int, beats: Int, subdivisions: Int, audibleBars: Int, silentBeats: Int? = nil,
        chooseAudibleBars: () -> Int = { GapCycle.fixedCounts.randomElement()! }
    ) -> Bool {
        guard audibleBars == GapCycle.random else {
            silentBeatsRemaining = GapCycle.silentBeatsRemaining(
                tick: tick, beats: beats, subdivisions: subdivisions,
                audibleBars: audibleBars, silentBeats: silentBeats)
            return silentBeatsRemaining > 0
        }
        guard tick >= 0 else { silentBeatsRemaining = 0; return false }
        let beat = tick / max(1, subdivisions)
        if beat == lastBeat { return silentBeatsRemaining > 0 }
        let meter = GapCycle.beatsPerBar(beats)
        let length = GapCycle.length(silentBeats, meter: meter)
        while beat >= cycleEndBeat {
            let choice = chooseAudibleBars()
            let count = GapCycle.fixedCounts.contains(choice) ? choice : 1
            silentStartBeat = cycleEndBeat + count * meter
            cycleEndBeat = silentStartBeat + length
        }
        silentBeatsRemaining = beat >= silentStartBeat ? cycleEndBeat - beat : 0
        lastBeat = beat
        return silentBeatsRemaining > 0
    }
}
