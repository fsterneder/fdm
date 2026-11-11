import XCTest
@testable import TempoCore

final class GapCycleTests: XCTestCase {
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
