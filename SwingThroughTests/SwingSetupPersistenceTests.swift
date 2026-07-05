import XCTest
import SwingKit
@testable import SwingThrough

@MainActor
final class SwingSetupPersistenceTests: XCTestCase {
    func testSetupSelectionsPersistOnJobForRetry() {
        let metadata = VideoPreflightMetadata(
            duration: 8, nominalFPS: 120, displayWidth: 1080,
            displayHeight: 1920, codec: "hvc1", isHDR: true
        )
        let job = AnalysisJobRecord(
            videoFileName: "Jobs/id/source.mov",
            view: .faceOn,
            club: "Driver",
            handednessPreference: .left,
            trimStart: 1.5,
            trimEnd: 6.5,
            sourceMetadata: metadata
        )

        XCTAssertEqual(job.view, .faceOn)
        XCTAssertEqual(job.club, "Driver")
        XCTAssertEqual(job.handednessPreference, .left)
        XCTAssertEqual(job.sourceWindow, 1.5...6.5)
        XCTAssertEqual(job.sourceFPS, 120)
        XCTAssertEqual(job.sourceCodec, "hvc1")
        XCTAssertEqual(job.sourceIsHDR, true)
    }
}
