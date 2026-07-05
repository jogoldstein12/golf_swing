// TEMPORARY debug harness — deleted once the shaft detector is validated.
import XCTest
import CoreGraphics
import simd
@testable import SwingKit

final class ShaftDebugTests: XCTestCase {
    func testShaftDetectorOnFixtureP1Frame() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("SwingThrough/Fixtures/sample_dtl.mp4")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("fixture not present")
        }
        let image: CGImage
        do {
            image = try await FrameImage.cgImage(from: fixture, at: 1.36)
        } catch {
            // Restricted CI/sandbox hosts can compile AVFoundation but deny the
            // decoder service. That is an environment limitation, not a shaft-math
            // failure; the on-device pipeline already treats this frame as optional.
            throw XCTSkip("host video decoder unavailable: \(error.localizedDescription)")
        }
        print("image \(image.width)x\(image.height)")
        guard let (data, w, h) = FrameImage.grayscale(image) else { return XCTFail("grayscale failed") }
        print("grayscale ok \(w)x\(h)")
        // Orientation check: average of top 20 rows (sky, bright) vs bottom 20 rows
        // (grass, darker).
        let topAvg = Double(data[0..<(20 * w)].reduce(0) { $0 + Int($1) }) / Double(20 * w)
        let botAvg = Double(data[((h - 20) * w)...].reduce(0) { $0 + Int($1) }) / Double(20 * w)
        print("top20 avg \(topAvg)  bottom20 avg \(botAvg)  (expect top >> bottom)")

        let grip = SIMD2(0.404, 0.498)
        let result = ShaftDetector.detectShaft(image: image, grip2: grip, groundY2: 0.7767)
        if let r = result {
            print("SHAFT FOUND ground=\(r.ground) upper=\(r.upper) contrast=\(r.contrast)")
        } else {
            print("SHAFT NOT FOUND")
        }
        XCTAssertNotNil(result)
    }
}
