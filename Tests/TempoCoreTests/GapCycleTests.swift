import XCTest
@testable import TempoCore

final class GapCycleTests: XCTestCase {
    func testConfiguredGapLengthsAcrossMetersAndSubdivisions() {
        for beats in 1...9 {
            for division in 1...4 {
                for bars in GapCycle.fixedCounts {
                    for length in 1...8 {
                        let audibleTicks = bars * beats * division
                        let silentTicks = length * division
                        let cycle = audibleTicks + silentTicks
                        for tick in 0..<(cycle * 2) {
                            let position = tick % cycle
                            let expected = position >= audibleTicks
                            let actual = GapCycle.isSilent(tick: tick, beats: beats,
                                subdivisions: division, audibleBars: bars, silentBeats: length)
                            XCTAssertEqual(actual, expected)
                            let remaining = GapCycle.silentBeatsRemaining(tick: tick, beats: beats,
                                subdivisions: division, audibleBars: bars, silentBeats: length)
                            XCTAssertEqual(remaining, expected ? length - (position - audibleTicks) / division : 0)
                        }
                    }
                }
            }
        }
    }
    func testFixedGapCountdownThenSubdivisionResumes() {
        var sequence = GapSequence()
        let expected = [0, 0, 0, 0, 2, 1, 0]
        for (beat, remaining) in expected.enumerated() {
            for subdivision in 0..<3 {
                let silent = sequence.isSilent(tick: beat * 3 + subdivision,
                    beats: 4, subdivisions: 3, audibleBars: 1, silentBeats: 2)
                XCTAssertEqual(silent, remaining > 0)
                XCTAssertEqual(sequence.silentBeatsRemaining, remaining)
            }
        }
    }
    func testRandomKeepsConfiguredLengthAndCountsDownOncePerBeat() {
        var sequence = GapSequence()
        let choices = [1, 4, 2]
        var draws = 0
        let silentBeats = [3, 4, 17, 18, 25, 26]
        for tick in 0..<(27 * 4) {
            let silent = sequence.isSilent(tick: tick, beats: 3, subdivisions: 4,
                audibleBars: GapCycle.random, silentBeats: 2) {
                    let result = choices[draws % choices.count]
                    draws += 1
                    return result
                }
            let beat = tick / 4
            XCTAssertEqual(silent, silentBeats.contains(beat))
            let expected = [3, 17, 25].contains(beat) ? 2 : ([4, 18, 26].contains(beat) ? 1 : 0)
            XCTAssertEqual(sequence.silentBeatsRemaining, expected)
        }
        XCTAssertEqual(draws, 3)
    }

    func testOffNeverMutes() {
        for tick in 0..<200 {
            XCTAssertFalse(GapCycle.isSilent(tick: tick, beats: 3, subdivisions: 4, audibleBars: 0))
        }
    }

    func testTwoAudibleBarsThenExactlyOneSilentBar() {
        // Six ticks per bar (3 beats, 2 subdivisions): sound 0–11, silence 12–17.
        XCTAssertFalse(GapCycle.isSilent(tick: 0, beats: 3, subdivisions: 2, audibleBars: 2))
        XCTAssertFalse(GapCycle.isSilent(tick: 11, beats: 3, subdivisions: 2, audibleBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 12, beats: 3, subdivisions: 2, audibleBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 17, beats: 3, subdivisions: 2, audibleBars: 2))
        XCTAssertFalse(GapCycle.isSilent(tick: 18, beats: 3, subdivisions: 2, audibleBars: 2))
    }

    func testNoAccentUsesFourPulseBars() {
        XCTAssertFalse(GapCycle.isSilent(tick: 7, beats: 0, subdivisions: 1, audibleBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 8, beats: 0, subdivisions: 1, audibleBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 11, beats: 0, subdivisions: 1, audibleBars: 2))
        XCTAssertFalse(GapCycle.isSilent(tick: 12, beats: 0, subdivisions: 1, audibleBars: 2))
    }

    func testEveryFixedSettingAlwaysMutesExactlyOneBar() {
        for count in GapCycle.fixedCounts {
            for division in 1...4 {
                let ticksPerBar = 9 * division
                let cycle = (count + 1) * ticksPerBar
                let silentTicks = (0..<cycle).filter {
                    GapCycle.isSilent(tick: $0, beats: 9, subdivisions: division, audibleBars: count)
                }
                XCTAssertEqual(silentTicks.count, ticksPerBar)
                XCTAssertFalse(GapCycle.isSilent(tick: cycle, beats: 9, subdivisions: division, audibleBars: count))
            }
        }
    }

    func testRandomChangesAudibleRunOncePerCycleAndNeverSilenceLength() {
        var sequence = GapSequence()
        let choices = [1, 4, 2]
        var draws = 0
        // Audible bar 0; silent 1; audible 2–5; silent 6; audible 7–8; silent 9.
        for tick in 0..<120 {
            let silent = sequence.isSilent(tick: tick, beats: 3, subdivisions: 4, audibleBars: GapCycle.random) {
                let value = choices[draws % choices.count]
                draws += 1
                return value
            }
            XCTAssertEqual(silent, [1, 6, 9].contains(tick / 12))
        }
        XCTAssertEqual(draws, 3)
    }

    func testRestartBeginsWithAudibleBar() {
        var sequence = GapSequence()
        XCTAssertFalse(sequence.isSilent(tick: 0, beats: 2, subdivisions: 1, audibleBars: GapCycle.random) { 1 })
        XCTAssertTrue(sequence.isSilent(tick: 2, beats: 2, subdivisions: 1, audibleBars: GapCycle.random) { 1 })
        sequence = GapSequence()
        XCTAssertFalse(sequence.isSilent(tick: 0, beats: 2, subdivisions: 1, audibleBars: GapCycle.random) { 4 })
    }
}
