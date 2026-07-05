import XCTest
@testable import SwingKit

final class VideoPreflightTests: XCTestCase {
    func testRejectsShortVideoMetadata() {
        let metadata = validMetadata(duration: 0.2)
        XCTAssertThrowsError(
            try VideoPreflightService.validate(metadata, limits: .init())
        ) { error in
            guard case VideoPreflightError.tooShort = error else {
                XCTFail("Expected tooShort, got \(error)")
                return
            }
        }
    }

    func testRejectsUnsupportedCodec() {
        var metadata = validMetadata()
        metadata.codec = "zzzz"
        XCTAssertThrowsError(
            try VideoPreflightService.validate(metadata, limits: .init())
        ) { error in
            XCTAssertEqual(error as? VideoPreflightError, .unsupportedCodec("zzzz"))
        }
    }

    func testAcceptsCommonHEVCMetadata() throws {
        let metadata = validMetadata(codec: "hvc1")
        XCTAssertNoThrow(try VideoPreflightService.validate(metadata, limits: .init()))
    }

    func testRejectsInvalidDimensions() {
        var metadata = validMetadata()
        metadata.displayWidth = 0
        XCTAssertThrowsError(
            try VideoPreflightService.validate(metadata, limits: .init())
        ) { error in
            XCTAssertEqual(error as? VideoPreflightError, .invalidDimensions)
        }
    }

    private func validMetadata(duration: Double = 5, codec: String = "avc1") -> VideoPreflightMetadata {
        VideoPreflightMetadata(
            duration: duration,
            nominalFPS: 60,
            displayWidth: 1920,
            displayHeight: 1080,
            codec: codec,
            isHDR: false
        )
    }
}
