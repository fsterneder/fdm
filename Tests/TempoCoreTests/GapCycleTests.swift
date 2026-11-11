import XCTest
@testable import TempoCore

final class GapCycleTests: XCTestCase {
    func testOffNeverMutes() {
        for tick in 0..<200 {
            XCTAssertFalse(GapCycle.isSilent(tick: tick, beats: 3, subdivisions: 4, audibleBars: 0, silentBars: 8))
        }
    }
    func testWholeBarGapsAcrossMetersAndSubdivisions() {
        for beats in 1...9 {
            for division in 1...4 {
                for audible in GapCycle.fixedCounts {
                    for length in GapCycle.lengthOptions {
                        let ticksPerBar = beats * division
                        let cycle = (audible + length) * ticksPerBar
                        for tick in 0..<(cycle * 2) {
                            let bar = (tick / ticksPerBar) % (audible + length)
                            let remaining = bar >= audible ? audible + length - bar : 0
                            XCTAssertEqual(GapCycle.isSilent(tick: tick, beats: beats,
                                subdivisions: division, audibleBars: audible, silentBars: length), remaining > 0)
                            XCTAssertEqual(GapCycle.silentBarsRemaining(tick: tick, beats: beats,
                                subdivisions: division, audibleBars: audible, silentBars: length), remaining)
                        }
                    }
                }
            }
        }
    }
    func testCountdownChangesOnlyOnBarBoundaries() {
        var sequence = GapSequence()
        let expected = [0, 2, 1, 0]
        for (bar, remaining) in expected.enumerated() {
            for tick in 0..<12 {
                let silent = sequence.isSilent(tick: bar * 12 + tick, beats: 3,
                    subdivisions: 4, audibleBars: 1, silentBars: 2)
                XCTAssertEqual(silent, remaining > 0)
                XCTAssertEqual(sequence.silentBarsRemaining, remaining)
            }
        }
    }
    func testRandomChoosesOncePerCycleAndKeepsFullSilentBars() {
        var sequence = GapSequence()
        let choices = [1, 4, 2]
        var draws = 0
        for tick in 0..<(13 * 12) {
            let silent = sequence.isSilent(tick: tick, beats: 3, subdivisions: 4,
                audibleBars: GapCycle.random, silentBars: 2) {
                    let result = choices[draws % choices.count]
                    draws += 1
                    return result
                }
            let bar = tick / 12
            let remaining = [1, 7, 11].contains(bar) ? 2 : ([2, 8, 12].contains(bar) ? 1 : 0)
            XCTAssertEqual(silent, remaining > 0)
            XCTAssertEqual(sequence.silentBarsRemaining, remaining)
        }
        XCTAssertEqual(draws, 3)
    }
    func testRestartBeginsWithAudibleBar() {
        var sequence = GapSequence()
        XCTAssertFalse(sequence.isSilent(tick: 0, beats: 2, subdivisions: 1,
            audibleBars: GapCycle.random, silentBars: 2) { 1 })
        XCTAssertTrue(sequence.isSilent(tick: 2, beats: 2, subdivisions: 1,
            audibleBars: GapCycle.random, silentBars: 2) { 1 })
        sequence = GapSequence()
        XCTAssertFalse(sequence.isSilent(tick: 0, beats: 2, subdivisions: 1,
            audibleBars: GapCycle.random, silentBars: 2) { 4 })
    }
    func testOldBeatLengthsMigrateToWholeBarsOnce() {
        XCTAssertEqual(GapCycle.restoredLength(savedBars: nil, legacyBeats: 4, beatsPerBar: 4), 1)
        XCTAssertEqual(GapCycle.restoredLength(savedBars: nil, legacyBeats: 8, beatsPerBar: 4), 2)
        XCTAssertEqual(GapCycle.restoredLength(savedBars: nil, legacyBeats: 5, beatsPerBar: 3), 2)
        XCTAssertEqual(GapCycle.restoredLength(savedBars: nil, legacyBeats: nil, beatsPerBar: 4), 1)
        XCTAssertEqual(GapCycle.restoredLength(savedBars: 3, legacyBeats: 8, beatsPerBar: 4), 3)
        XCTAssertEqual(GapCycle.restoredLength(savedBars: 20, legacyBeats: nil, beatsPerBar: 4), 8)
    }
}
