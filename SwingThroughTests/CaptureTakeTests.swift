import XCTest
import SwingKit
@testable import SwingThrough

@MainActor
final class CaptureTakeTests: XCTestCase {
    // A take records the ACHIEVED capture format — the real dimensions and frame rate the
    // camera produced — not just fps. These travel with the clip to review.
    func testCaptureTakeCarriesAchievedDimensionsAndFPS() {
        let url = URL(fileURLWithPath: "/tmp/swing-test.mov")
        let take = CaptureTake(url: url, view: .downTheLine,
                               fps: 60, duration: 4.2,
                               width: 1080, height: 1920)

        XCTAssertEqual(take.fps, 60)
        XCTAssertEqual(take.width, 1080)
        XCTAssertEqual(take.height, 1920)
        // Portrait short axis is the "1080p"-class figure honestly recorded from the feed.
        XCTAssertEqual(min(take.width, take.height), 1080)
    }

    func testCaptureTakeEquatableIncludesDimensions() {
        let url = URL(fileURLWithPath: "/tmp/swing-test.mov")
        let base = CaptureTake(url: url, view: .faceOn, fps: 60, duration: 3,
                               width: 1080, height: 1920)
        let differentSize = CaptureTake(url: url, view: .faceOn, fps: 60, duration: 3,
                                        width: 720, height: 1280)
        XCTAssertNotEqual(base, differentSize)
    }
}
