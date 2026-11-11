/// Restores legacy No Accent preferences and keeps accent independent of meter.
public struct BeatPattern {
    public let beats: Int
    public let accent: Bool
    public init(savedBeats: Int, savedAccent: Bool?) {
        let legacyNoAccent = savedAccent == nil && (savedBeats == 0 || savedBeats == 1)
        beats = legacyNoAccent ? 4 : min(9, max(1, savedBeats))
        accent = savedAccent ?? !legacyNoAccent
    }
    /// Voice buffers: 0 = accented beat, 1 = regular beat, 2 = subdivision.
    public static func soundKind(beat: Int, isMainBeat: Bool, accent: Bool) -> Int {
        if !isMainBeat { return 2 }
        return accent && beat == 0 ? 0 : 1
    }
}
