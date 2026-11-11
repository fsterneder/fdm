public enum GapCycle {
    public static let options = [0, 1, 2, 4]

    /// One audible bar followed by the selected number of silent bars, repeating.
    /// No-accent mode uses four pulses per bar without adding an audible accent.
    public static func isSilent(tick: Int, beats: Int, subdivisions: Int, silentBars: Int) -> Bool {
        guard tick >= 0, silentBars > 0, options.contains(silentBars) else { return false }
        let pulsesPerBar = beats == 0 ? 4 : max(1, beats)
        let ticksPerBar = pulsesPerBar * max(1, subdivisions)
        let bar = tick / ticksPerBar
        return bar % (silentBars + 1) != 0
    }
}
