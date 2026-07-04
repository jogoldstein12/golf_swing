import XCTest
@testable import SwingKit

final class FiltersMathTests: XCTestCase {
    /// A clean parabola y = -(t-2.3)^2 sampled on an integer grid: the discrete max is
    /// at t=2 or t=3, but the true peak is at t=2.3 — parabolicPeak should recover
    /// that sub-frame time.
    func testParabolicPeakSubFrameRecovery() {
        let t = (0...6).map(Double.init)
        let peakT = 2.3
        let y = t.map { -pow($0 - peakT, 2) }
        let discretePeakIdx = y.enumerated().max(by: { $0.element < $1.element })!.offset
        let (time, value) = Filters.parabolicPeak(t: t, y: y, at: discretePeakIdx)
        XCTAssertEqual(time, peakT, accuracy: 0.02)
        XCTAssertEqual(value, 0.0, accuracy: 0.02)
    }

    func testParabolicPeakAtExactSample() {
        let t = (0...6).map(Double.init)
        let y = t.map { -pow($0 - 3.0, 2) }
        let (time, value) = Filters.parabolicPeak(t: t, y: y, at: 3)
        XCTAssertEqual(time, 3.0, accuracy: 1e-9)
        XCTAssertEqual(value, 0.0, accuracy: 1e-9)
    }

    /// A linear ramp crossing zero between two samples: zeroCrossing should recover
    /// the exact sub-frame crossing time.
    func testZeroCrossingSubFrameRecovery() {
        let t = [0.0, 0.04, 0.08, 0.12, 0.16]
        // crosses zero at t = 0.10 (between index 2 (t=0.08,y=-0.2) and 3 (t=0.12,y=0.2))
        let y = [-1.0, -0.6, -0.2, 0.2, 0.6]
        let crossing = Filters.zeroCrossing(t: t, y: y, after: 2)
        XCTAssertNotNil(crossing)
        XCTAssertEqual(crossing ?? -1, 0.10, accuracy: 1e-9)
    }

    func testZeroCrossingReturnsNilWithoutSignChange() {
        let t = [0.0, 1.0, 2.0]
        let y = [1.0, 2.0, 3.0]
        XCTAssertNil(Filters.zeroCrossing(t: t, y: y, after: 0))
    }

    func testHampelRejectsSingleFrameOutlier() {
        var x = [Double](repeating: 1.0, count: 11)
        x[5] = 50.0 // single spike
        let cleaned = Filters.hampel(x)
        XCTAssertEqual(cleaned[5], 1.0, accuracy: 1e-9)
        // Neighbors untouched.
        XCTAssertEqual(cleaned[4], 1.0, accuracy: 1e-9)
    }

    func testSavitzkyGolayPreservesLinearRamp() {
        let x = (0..<20).map { Double($0) * 2.5 }
        let smoothed = Filters.savitzkyGolay(x)
        for i in 4..<16 { // interior, away from reflected edges
            XCTAssertEqual(smoothed[i], x[i], accuracy: 1e-9)
        }
    }

    func testUnwrapDegreesRemovesJump() {
        let wrapped = [170.0, 178.0, -179.0, -172.0]
        let unwrapped = Filters.unwrapDegrees(wrapped)
        XCTAssertEqual(unwrapped[0], 170, accuracy: 1e-9)
        XCTAssertEqual(unwrapped[2], 181, accuracy: 1e-9) // -179 + 360
        XCTAssertEqual(unwrapped[3], 188, accuracy: 1e-9)
    }
}
