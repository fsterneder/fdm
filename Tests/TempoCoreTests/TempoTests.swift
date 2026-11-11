import XCTest
@testable import TempoCore
final class TempoTests: XCTestCase {
    func testTempoDraftAcceptsOnlyUpToThreeDigits() {
        for text in ["", "3", "30", "120", "252", "999", "030"] {
            XCTAssertTrue(Tempo.isValidDraft(text), text)
        }
        for text in ["abc", "120 BPM", "-5", "+90", "12.5", "1e2", "1234", " 90", "١٢٠", "１２３"] {
            XCTAssertFalse(Tempo.isValidDraft(text), text)
        }
    }
    func testDirectTempoEntry() {
        XCTAssertEqual(Tempo.fromText(" 120 "), 120)
        XCTAssertEqual(Tempo.fromText("300"), 252)
        XCTAssertEqual(Tempo.fromText("-5"), 30)
        XCTAssertNil(Tempo.fromText(""))
        XCTAssertNil(Tempo.fromText("abc"))
        XCTAssertNil(Tempo.fromText("120.5"))
        XCTAssertNil(Tempo.fromText(String(repeating: "9", count: 40)))
    }
    func testTempoBounds() {
        XCTAssertEqual(Tempo.clamp(0), 30)
        XCTAssertEqual(Tempo.clamp(300), 252)
    }
    func testSampleGridDoesNotAccumulateRoundingDrift() {
        let interval = Tempo.frames(bpm: 137, subdivisions: 3, sampleRate: 48_000)
        let last = (interval * 10_000).rounded()
        XCTAssertLessThanOrEqual(abs(last - 48_000 * 60 * 10_000 / 137 / 3), 0.5)
    }
    func testTapAverageAndPauseReset() {
        var taps = TapTempo()
        XCTAssertNil(taps.tap(at: 0))
        XCTAssertEqual(taps.tap(at: 0.5), 120)
        XCTAssertEqual(taps.tap(at: 1), 120)
        XCTAssertNil(taps.tap(at: 4))
        XCTAssertEqual(taps.tap(at: 5), 60)
    }
    func testNonMonotonicTapResets() {
        var taps = TapTempo()
        XCTAssertNil(taps.tap(at: 1))
        XCTAssertNil(taps.tap(at: 1))
        XCTAssertNil(taps.tap(at: 0))
    }
}
