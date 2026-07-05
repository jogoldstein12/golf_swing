import XCTest
@testable import SwingThrough

@MainActor
final class CaptureCuesTests: XCTestCase {
    // The three "something happened" transitions each map to exactly one cue. This is the
    // whole audio contract, proven with no audio session or synthesizer involved.
    func testArmedTriggeredCapturedMapToCues() {
        XCTAssertEqual(CaptureCues.cue(for: .armed), .armed)
        XCTAssertEqual(CaptureCues.cue(for: .triggered), .recordingStarted)
        XCTAssertEqual(CaptureCues.cue(for: .captured(trimFrom: 1, trimTo: 4)),
                       .swingCaptured)
    }

    // Bookkeeping events stay silent — no chime, no speech.
    func testBookkeepingEventsProduceNoCue() {
        XCTAssertNil(CaptureCues.cue(for: .recordStart))
        XCTAssertNil(CaptureCues.cue(for: .recordCancel))
        XCTAssertNil(CaptureCues.cue(for: .disarmed(.timeout)))
        XCTAssertNil(CaptureCues.cue(for: .disarmed(.walking)))
    }

    func testCountdownWords() {
        XCTAssertEqual(CaptureCues.countdownWord(3), "three")
        XCTAssertEqual(CaptureCues.countdownWord(2), "two")
        XCTAssertEqual(CaptureCues.countdownWord(1), "one")
    }
}
