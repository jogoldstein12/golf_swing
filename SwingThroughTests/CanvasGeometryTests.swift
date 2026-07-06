// NP-2 — CanvasGeometry must reproduce the video pane's COVER (fill) mapping, never a
// letterbox (aspect-fit) one: VideoAnalysisView renders the video scaled to fully cover
// its pane (VideoPaneLayout.scale = max(...)), so a portrait clip in a squarer pane
// overflows top/bottom rather than leaving bars. Any overlay using a different mapping
// would visibly drift off the video's own pixels.
import XCTest
import SwingKit
@testable import SwingThrough

final class CanvasGeometryTests: XCTestCase {

    private let videoSize = CGSize(width: 1080, height: 1920)
    private let rect = CGRect(x: 0, y: 0, width: 300, height: 300)

    func testCoverScaleIsChosenNotLetterbox() {
        // cover scale = max(300/1080, 300/1920) = 300/1080 ≈ 0.2778 — the WIDTH ratio
        // wins because the video is taller (relatively) than the square pane, so
        // covering the pane's width requires more magnification than covering its
        // height. A letterbox (aspect-fit) mapping would instead choose the SMALLER
        // ratio and keep the whole image inside the 300x300 box.
        let p = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: 0.5), videoSize: videoSize, in: rect)
        XCTAssertEqual(p.x, 150, accuracy: 0.5)
        XCTAssertEqual(p.y, 150, accuracy: 0.5)
    }

    func testHorizontalCenterMapsToRectMidX() {
        // Any point with normalized x = 0.5 lands on the rect's horizontal midpoint —
        // the display width matches the rect width exactly under cover scale.
        for ny: CGFloat in [0.0, 0.25, 0.75, 1.0] {
            let p = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: ny), videoSize: videoSize, in: rect)
            XCTAssertEqual(p.x, 150, accuracy: 0.5, "x should stay at rect mid regardless of y")
        }
    }

    func testVerticalOverflowMatchesCoverNotLetterbox() {
        // displaySize ≈ (300, 533.3), centered on the 300-tall rect → top/bottom of the
        // full frame land OUTSIDE [0, 300]. A letterbox mapping would instead clamp the
        // whole image inside the rect (y in [0, 300]) — the opposite behavior.
        let top = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: 0.0), videoSize: videoSize, in: rect)
        let bottom = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: 1.0), videoSize: videoSize, in: rect)

        XCTAssertEqual(top.y, 150 - 266.7, accuracy: 1.0)
        XCTAssertEqual(bottom.y, 150 + 266.7, accuracy: 1.0)

        // The overflow is the tell: cover mapping puts these well outside the rect;
        // letterbox mapping never would.
        XCTAssertLessThan(top.y, 0)
        XCTAssertGreaterThan(bottom.y, rect.height)
    }

    func testAnchorMatchesBasePlaneLine2DFirstPoint() {
        // The line the overlay anchors every ray to is basePlaneLine2D[0] (ground/ball
        // end) — mapping it directly must agree with whatever PlaneOverlay uses as its
        // own anchor, within a point of drawing tolerance.
        let line: [SIMD2<Double>] = [SIMD2(0.585, 0.802), SIMD2(0.253, 0.318)]
        let anchorViaSIMD = CanvasGeometry.imagePoint(line[0], videoSize: videoSize, in: rect)
        let anchorViaCGPoint = CanvasGeometry.imagePoint(
            CGPoint(x: line[0].x, y: line[0].y), videoSize: videoSize, in: rect
        )
        XCTAssertEqual(anchorViaSIMD.x, anchorViaCGPoint.x, accuracy: 1.0)
        XCTAssertEqual(anchorViaSIMD.y, anchorViaCGPoint.y, accuracy: 1.0)

        // Sanity: it lands within the expected cover-mapped range for this fixture.
        // scale ≈ 0.27778; origin ≈ (0, -116.667); x = 0.585*300 = 175.5;
        // y = -116.667 + 0.802*533.333 ≈ 311.07
        XCTAssertEqual(anchorViaSIMD.x, 175.5, accuracy: 1.0)
        XCTAssertEqual(anchorViaSIMD.y, 311.07, accuracy: 1.0)
    }

    func testDegenerateVideoSizeDoesNotCrashOrProduceNaN() {
        // Zero-size video is never real, but the mapping must stay finite (defensive —
        // VideoPaneLayout already guards its divisors with max(_, 1)).
        let p = CanvasGeometry.imagePoint(CGPoint(x: 0.5, y: 0.5), videoSize: .zero, in: rect)
        XCTAssertFalse(p.x.isNaN)
        XCTAssertFalse(p.y.isNaN)
    }
}
