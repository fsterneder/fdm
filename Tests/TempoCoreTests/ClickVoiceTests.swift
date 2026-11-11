import XCTest
@testable import TempoCore

final class ClickVoiceTests: XCTestCase {
    func testSavedVoiceNumbersRemainStable() {
        XCTAssertEqual(ClickVoice(rawValue: 0), .click)
        XCTAssertEqual(ClickVoice(rawValue: 1), .wood)
        XCTAssertEqual(ClickVoice(rawValue: 2), .bright)
        XCTAssertEqual(ClickVoice.allCases.count, 5)
    }

    func testNewVoicesHaveCleanEndsAndFitFastestSubdivision() {
        for rate in [44_100.0, 48_000.0] {
            let interval = Tempo.frames(bpm: 252, subdivisions: 4, sampleRate: rate)
            for voice in [ClickVoice.clave, .softPulse] {
                for kind in 0...2 {
                    let samples = voice.samples(kind: kind, sampleRate: rate)
                    XCTAssertFalse(samples.isEmpty)
                    XCTAssertLessThan(Double(samples.count), interval)
                    XCTAssertEqual(samples.first!, 0, accuracy: 0.000001)
                    XCTAssertEqual(samples.last!, 0, accuracy: 0.000001)
                    XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
                    XCTAssertTrue(samples.contains { abs($0) > 0.01 })
                }
            }
        }
    }

    func testAccentAndSubdivisionLevels() {
        for voice in [ClickVoice.clave, .softPulse] {
            let energy = (0...2).map { kind -> Double in
                let samples = voice.samples(kind: kind, sampleRate: 48_000)
                return samples.reduce(0.0) { $0 + Double($1 * $1) }
            }
            XCTAssertGreaterThan(energy[0], energy[1])
            XCTAssertGreaterThan(energy[1], energy[2])
        }
    }

    func testNewVoicesAreDistinct() {
        XCTAssertNotEqual(ClickVoice.clave.samples(kind: 1, sampleRate: 48_000),
                          ClickVoice.softPulse.samples(kind: 1, sampleRate: 48_000))
    }
}
