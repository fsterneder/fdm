import XCTest
@testable import TempoCore

final class GapCycleTests: XCTestCase {
    func testGapOffNeverMutes() {
        for tick in 0..<100 {
            XCTAssertFalse(GapCycle.isSilent(tick: tick, beats: 3, subdivisions: 4, silentBars: 0))
        }
    }

    func testOneAudibleBarThenTwoSilentBars() {
        // Three beats per bar, two subdivisions per beat: six ticks in each bar.
        XCTAssertFalse(GapCycle.isSilent(tick: 5, beats: 3, subdivisions: 2, silentBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 6, beats: 3, subdivisions: 2, silentBars: 2))
        XCTAssertTrue(GapCycle.isSilent(tick: 17, beats: 3, subdivisions: 2, silentBars: 2))
        XCTAssertFalse(GapCycle.isSilent(tick: 18, beats: 3, subdivisions: 2, silentBars: 2))
    }

    func testNoAccentUsesFourPulseBars() {
        XCTAssertFalse(GapCycle.isSilent(tick: 3, beats: 0, subdivisions: 1, silentBars: 1))
        XCTAssertTrue(GapCycle.isSilent(tick: 4, beats: 0, subdivisions: 1, silentBars: 1))
        XCTAssertFalse(GapCycle.isSilent(tick: 8, beats: 0, subdivisions: 1, silentBars: 1))
    }

    func testEachGapLengthAndDivision() {
        for gap in [1, 2, 4] {
            for division in 1...4 {
                let ticksPerBar = 9 * division
                let cycle = (gap + 1) * ticksPerBar
                let silentTicks = (0..<cycle).filter {
                    GapCycle.isSilent(tick: $0, beats: 9, subdivisions: division, silentBars: gap)
                }
                XCTAssertEqual(silentTicks.count, gap * ticksPerBar)
                XCTAssertFalse(GapCycle.isSilent(tick: cycle, beats: 9, subdivisions: division, silentBars: gap))
            }
        }
    }
}
