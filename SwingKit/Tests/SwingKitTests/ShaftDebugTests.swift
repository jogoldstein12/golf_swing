// TEMPORARY debug harness — deleted once the shaft detector is validated.
import XCTest
import simd
@testable import SwingKit

final class ShaftDebugTests: XCTestCase {
    func testShaftDetectorOnFixtureP1Frame() throws {
        let fixture = URL(fileURLWithPath: "/Users/nancycolesmd/Documents/golf_swing/SwingThrough/Fixtures/sample_dtl.mp4")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("fixture not present")
        }
        let image = try FrameImage.cgImage(from: fixture, at: 1.36)
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
