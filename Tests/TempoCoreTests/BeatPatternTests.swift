import XCTest
@testable import TempoCore

final class BeatPatternTests: XCTestCase {
    func testLegacyNoAccentMigratesToFourBeatsWithAccentOff() {
        for saved in [0, 1] {
            let pattern = BeatPattern(savedBeats: saved, savedAccent: nil)
            XCTAssertEqual(pattern.beats, 4)
            XCTAssertFalse(pattern.accent)
        }
    }
    func testExplicitOneBeatAndAccentAreIndependent() {
        for accent in [false, true] {
            let pattern = BeatPattern(savedBeats: 1, savedAccent: accent)
            XCTAssertEqual(pattern.beats, 1)
            XCTAssertEqual(pattern.accent, accent)
        }
        let normal = BeatPattern(savedBeats: 3, savedAccent: nil)
        XCTAssertEqual(normal.beats, 3)
        XCTAssertTrue(normal.accent)
    }
    func testAccentOffUsesRegularClicksWithoutChangingSubdivisionVoice() {
        XCTAssertEqual(BeatPattern.soundKind(beat: 0, isMainBeat: true, accent: true), 0)
        XCTAssertEqual(BeatPattern.soundKind(beat: 0, isMainBeat: true, accent: false), 1)
        for accent in [false, true] {
            XCTAssertEqual(BeatPattern.soundKind(beat: 1, isMainBeat: true, accent: accent), 1)
            XCTAssertEqual(BeatPattern.soundKind(beat: 0, isMainBeat: false, accent: accent), 2)
        }
    }
}
