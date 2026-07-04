// Address-frame shaft-line detector: finds the club shaft as the dominant straight
// edge in the corridor below the grip, directly on pixels (no ML). This is the one
// place the pipeline looks at the image itself rather than joint tracks, because the
// club isn't a tracked joint.
//
// Method: a constrained Hough-style search. We already know one point the line passes
// near (the grip), so instead of a full (angle, offset) accumulator over the whole
// image we sweep angle only, with a small offset search around the grip to absorb the
// grip point's own localization error, and score each candidate by how well its pixels
// align with a strong, consistent image gradient *perpendicular to the candidate line*
// (a real edge has gradient perpendicular to itself; grass/noise doesn't line up).
// Quality-gated: fails closed (nil) rather than ever inventing a line — callers fall
// back to grip->ball, and ultimately to "plane unavailable".
import CoreGraphics
import Foundation
import simd

enum ShaftDetector {
    struct Options {
        var searchDegrees: ClosedRange<Double> = (-82)...82   // from straight down (0°)
        var angleStepDegrees: Double = 0.5
        /// Perpendicular offset search radius around the grip anchor, as a fraction
        /// of image height. Resolution-relative because the grip estimate's pixel
        /// error scales with resolution — a fixed ±6px was validated to be too tight
        /// at 2560p (the smoothed grip can sit ~10px off the shaft's centerline and
        /// no angle can then track the shaft over its full length). Floored at 6px.
        var offsetSearchFraction: Double = 0.007
        var samplesAlongLine: Int = 40
        /// Best line's average perpendicular-gradient score must exceed the corridor
        /// background average by at least this factor.
        var minContrastRatio: Double = 1.6
        /// Fraction of samples along the best line that must individually clear a
        /// floor gradient (rejects a single strong point masquerading as an edge).
        var minOnLineFraction: Double = 0.55
        init() {}
    }

    /// `grip2`/`ankles` in our normalized top-left-origin contract. Returns the
    /// detected line as two pixel points (ground end, grip-side end) plus the
    /// contrast ratio actually achieved (for logging), or nil if the quality gate
    /// wasn't cleared.
    static func detectShaft(image: CGImage, grip2: SIMD2<Double>, groundY2: Double,
                            options: Options = .init()) -> (ground: CGPoint, upper: CGPoint, contrast: Double)? {
        guard let (data, w, h) = FrameImage.grayscale(image) else { return nil }
        let gripPx = CGPoint(x: grip2.x * Double(w), y: grip2.y * Double(h))
        let corridorLen = max(20.0, groundY2 * Double(h) - gripPx.y)
        guard corridorLen > 15 else { return nil }

        func luminance(_ x: Double, _ y: Double) -> Double? {
            guard x >= 1, y >= 1, x < Double(w - 1), y < Double(h - 1) else { return nil }
            let xi = Int(x), yi = Int(y)
            return Double(data[yi * w + xi])
        }
        // Local gradient via central differences.
        func gradient(_ x: Double, _ y: Double) -> SIMD2<Double>? {
            guard let l = luminance(x + 1, y), let r = luminance(x - 1, y),
                  let d = luminance(x, y + 1), let u = luminance(x, y - 1) else { return nil }
            return SIMD2((l - r) / 2, (d - u) / 2)
        }

        let offsetSearchPx = max(6.0, options.offsetSearchFraction * Double(h))
        let offsetStepPx = max(1.0, offsetSearchPx / 8)

        var best: (angle: Double, offset: Double, score: Double, samples: [Double])?
        var deg = options.searchDegrees.lowerBound
        while deg <= options.searchDegrees.upperBound {
            let rad = deg * .pi / 180
            let dir = SIMD2(sin(rad), cos(rad))         // 0deg = straight down (0,1)
            let normal = SIMD2(-dir.y, dir.x)            // perpendicular, unit length

            var offset = -offsetSearchPx
            while offset <= offsetSearchPx {
                let origin = SIMD2(gripPx.x, gripPx.y) + normal * offset
                var scores: [Double] = []
                scores.reserveCapacity(options.samplesAlongLine)
                for s in 0..<options.samplesAlongLine {
                    let t = corridorLen * Double(s) / Double(options.samplesAlongLine - 1)
                    let p = origin + dir * t
                    guard let g = gradient(p.x, p.y) else { continue }
                    scores.append(abs(dot(g, normal)))
                }
                guard scores.count > options.samplesAlongLine / 2 else { offset += offsetStepPx; continue }
                let avg = scores.reduce(0, +) / Double(scores.count)
                if best == nil || avg > best!.score {
                    best = (deg, offset, avg, scores)
                }
                offset += offsetStepPx
            }
            deg += options.angleStepDegrees
        }
        guard let winner = best else { return nil }

        // Background gradient magnitude over the whole corridor bounding box, as the
        // contrast baseline.
        let boxX0 = max(1, Int(gripPx.x - corridorLen))
        let boxX1 = min(w - 2, Int(gripPx.x + corridorLen))
        let boxY0 = max(1, Int(gripPx.y))
        let boxY1 = min(h - 2, Int(gripPx.y + corridorLen))
        var bgSum = 0.0, bgCount = 0
        if boxX1 > boxX0, boxY1 > boxY0 {
            let strideStep = max(1, (boxX1 - boxX0) / 40)
            var y = boxY0
            while y <= boxY1 {
                var x = boxX0
                while x <= boxX1 {
                    if let g = gradient(Double(x), Double(y)) { bgSum += length(g); bgCount += 1 }
                    x += strideStep
                }
                y += max(1, (boxY1 - boxY0) / 40)
            }
        }
        let bgAvg = bgCount > 0 ? bgSum / Double(bgCount) : 0
        guard bgAvg > 0, winner.score / bgAvg >= options.minContrastRatio else { return nil }
        let onLineFraction = Double(winner.samples.filter { $0 > winner.score * 0.4 }.count) / Double(winner.samples.count)
        guard onLineFraction >= options.minOnLineFraction else { return nil }

        let rad = winner.angle * .pi / 180
        let dir = SIMD2(sin(rad), cos(rad))
        let normal = SIMD2(-dir.y, dir.x)
        let origin = SIMD2(gripPx.x, gripPx.y) + normal * winner.offset
        let ground = origin + dir * corridorLen
        // Upper end: extend the same distance again past the grip, the other way,
        // so the drawn line reads as a full base-plane reference (ball, through the
        // hands, on up past the shoulder) rather than stopping at the grip.
        let upper = origin - dir * corridorLen

        return (CGPoint(x: ground.x, y: ground.y), CGPoint(x: upper.x, y: upper.y), winner.score / bgAvg)
    }

    /// Fallback ball detector: a small, smooth (low local-variance), locally-contrasting
    /// blob within `searchRegion` (pixel rect). Returns its center or nil.
    static func detectBall(image: CGImage, searchRegion: CGRect) -> CGPoint? {
        guard let (data, w, h) = FrameImage.grayscale(image) else { return nil }
        let x0 = max(1, Int(searchRegion.minX)), x1 = min(w - 2, Int(searchRegion.maxX))
        let y0 = max(1, Int(searchRegion.minY)), y1 = min(h - 2, Int(searchRegion.maxY))
        guard x1 > x0 + 6, y1 > y0 + 6 else { return nil }

        let win = 4 // half-window for the candidate blob patch
        var bestScore = -Double.infinity
        var bestCenter: CGPoint?
        var y = y0 + win
        while y <= y1 - win {
            var x = x0 + win
            while x <= x1 - win {
                var sum = 0.0, sumSq = 0.0, n = 0.0
                for dy in -win...win {
                    for dx in -win...win {
                        let v = Double(data[(y + dy) * w + (x + dx)])
                        sum += v; sumSq += v * v; n += 1
                    }
                }
                let mean = sum / n
                let variance = max(0, sumSq / n - mean * mean)
                // Ring around the patch, for local contrast.
                var ringSum = 0.0, ringN = 0.0
                let ring = win + 3
                for dy in [-ring, ring] {
                    for dx in -ring...ring { ringSum += Double(data[max(0, min(h - 1, y + dy)) * w + max(0, min(w - 1, x + dx))]); ringN += 1 }
                }
                for dx in [-ring, ring] {
                    for dy in -ring...ring { ringSum += Double(data[max(0, min(h - 1, y + dy)) * w + max(0, min(w - 1, x + dx))]); ringN += 1 }
                }
                let ringMean = ringN > 0 ? ringSum / ringN : mean
                let contrast = abs(mean - ringMean)
                // Smooth (low variance) AND locally distinct from its surroundings.
                let score = contrast - 0.5 * sqrt(variance)
                if score > bestScore { bestScore = score; bestCenter = CGPoint(x: x, y: y) }
                x += 2
            }
            y += 2
        }
        guard bestScore > 6 else { return nil } // empirically-set floor; documented in VALIDATION.md
        return bestCenter
    }
}
