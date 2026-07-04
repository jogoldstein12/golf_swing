// Turns a raw `[PoseFrame]` (25 fps, occasional fully-missing frames, real Vision
// noise) into a continuously-sampleable track: gap-filled, lightly smoothed, and
// grounded so the feet sit at scene y≈0.
//
// Coordinate note (verified empirically against the fixture — see
// docs/VALIDATION.md-style reasoning below, since j3's convention isn't spelled out
// beyond "meters, +y up, root(pelvis) at origin"): `pelvis`, `hipL`, `hipR` are
// numerically IDENTICAL across all 187 fixture frames (zero variance) — Vision's 3D
// body space is a body-anchored frame (origin at the pelvis, hip line pinned to a
// fixed local axis), not a world/camera frame. Whole-body yaw (the hips/shoulders
// physically turning during the swing) is normalized away and is NOT recoverable
// from j3 alone — reconstructing it from `cameraTransform` was tried and produced
// noisy, non-monotonic yaw (frame-to-frame swings of tens of degrees with no clean
// correlation to swing phase), so it is not used here. What IS real and clean in
// j3: arm swing, spine tilt, knee flex, and weight shift all show large, smooth,
// anatomically correct motion (verified by rendering the raw skeleton at each
// checkpoint and reading it against the swing — it clearly reads as address →
// takeaway → top → impact → finish). The avatar therefore renders joints directly
// in this body-local frame; the figure doesn't yaw, but every real deflection in
// the tracked data (which is most of what makes a golf swing look like a golf
// swing from a 3/4 angle) comes through faithfully.
import Foundation
import simd
import SwingKit

struct FittedPlane {
    var normal: SIMD3<Double>
    var point: SIMD3<Double>
    var angleDeg: Double
    var radius: Double
}

/// A prepared, time-continuous version of one recorded swing.
struct AvatarTrack {
    private(set) var times: [Double] = []
    /// Gap-filled + smoothed per-frame joint positions, index-aligned with `times`.
    /// NOT grounded — `pose(at:)` grounds at query time so grounding always reflects
    /// the actual interpolated ankle height at that instant.
    private(set) var raw: [[Joint: SIMD3<Double>]] = []

    var startTime: Double { times.first ?? 0 }
    var endTime: Double { times.last ?? 0 }

    init(frames: [PoseFrame]) {
        guard !frames.isEmpty else { return }
        let sorted = frames.sorted { $0.time < $1.time }
        times = sorted.map(\.time)
        let dense = Self.fillGaps(sorted.map { $0.j3.isEmpty ? nil : $0.j3 }, times: times)
        raw = Self.smoothed(dense)
    }

    /// Interpolated, grounded pose at an arbitrary time (clamped to track bounds).
    /// Catmull-Rom across the 4 neighboring samples for a smooth in-between (plain
    /// linear would facet visibly during the ~150 ms downswing at 25 fps).
    func pose(at t: Double) -> [Joint: SIMD3<Double>] {
        guard !times.isEmpty else { return [:] }
        let clamped = min(max(t, times[0]), times[times.count - 1])
        var lo = 0, hi = times.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if times[mid] <= clamped { lo = mid } else { hi = mid }
        }
        let i1 = lo, i2 = min(hi, times.count - 1)
        let t1 = times[i1], t2 = times[i2]
        let f = t2 > t1 ? (clamped - t1) / (t2 - t1) : 0
        let i0 = max(0, i1 - 1), i3 = min(times.count - 1, i2 + 1)

        var result: [Joint: SIMD3<Double>] = [:]
        for joint in Joint.allCases {
            guard let p1 = raw[i1][joint], let p2 = raw[i2][joint] else { continue }
            let p0 = raw[i0][joint] ?? p1
            let p3 = raw[i3][joint] ?? p2
            result[joint] = Self.catmullRom(p0, p1, p2, p3, f)
        }
        return Self.grounded(result)
    }

    /// The grip proxy (wrist midpoint) sampled densely across just the swing arc —
    /// address through impact — in the same grounded scene space as `pose(at:)`.
    /// Feeds both the path ribbon and the plane fit. See `swingArcBounds()`: a
    /// recorded clip runs longer than just the swing (a held address, a held
    /// finish), and this deliberately excludes that so both consumers only ever
    /// see the actual swing.
    func gripPath(samples: Int = 220) -> [SIMD3<Double>] {
        guard times.count > 1, samples > 1 else { return [] }
        let (t0, t1) = swingArcBounds()
        guard t1 > t0 else { return [] }
        return (0..<samples).map { i in
            let t = t0 + (t1 - t0) * Double(i) / Double(samples - 1)
            let p = pose(at: t)
            if let l = p[.wristL], let r = p[.wristR] { return (l + r) * 0.5 }
            return p[.wristL] ?? p[.wristR] ?? SIMD3<Double>()
        }
    }

    /// Infers the address→impact time bounds from the grip-height profile alone
    /// (this track carries no checkpoint times). A recorded clip is longer than
    /// just the swing — it typically holds a static address (often with a small
    /// waggle) before takeaway, and holds the finish afterward for the camera —
    /// and a naive fit across the *whole* clip has real problems: the path ribbon
    /// reads as a tangled knot (address-hold jitter, backswing, downswing, and a
    /// held-finish loop all overlapping) instead of one clean swing arc, and, in
    /// this fixture, the held finish is actually *higher* than the true top of
    /// backswing, so a plain global-max search picks the wrong point entirely.
    /// Top of backswing always falls well before a held finish, so the peak
    /// search is restricted to the earlier part of the clip; address and impact
    /// are then the nearest moments on either side, before/after, where the grip
    /// is still down near its resting height, ahead of the sustained rise/fall
    /// into the backswing and out of the follow-through.
    private func swingArcBounds() -> (start: Double, end: Double) {
        let fallback = (startTime, endTime)
        guard times.count > 12 else { return fallback }
        let heights: [Double] = raw.map { sample in
            if let l = sample[.wristL], let r = sample[.wristR] { return (l.y + r.y) * 0.5 }
            return sample[.wristL]?.y ?? sample[.wristR]?.y ?? 0
        }
        let n = heights.count
        // Light smoothing only — just enough to kill single-frame jitter. A wider
        // window (tried first) blurs the real, fairly brief top-of-backswing peak
        // down until it reads *lower* than an earlier takeaway wobble, which then
        // gets mis-picked as "top" instead.
        let smoothed = Self.movingAverage(heights, halfWindow: max(2, n / 60))

        // Top of backswing consistently falls in roughly the first half of a full
        // swing-through-finish recording in practice (backswing+downswing vs. a
        // held finish for the camera) — validated against the sample fixture,
        // where restricting the search this way is what keeps it from reaching
        // into the finish's rise, which is otherwise taller than the real top.
        let searchEnd = max(1, Int(Double(n) * 0.5))
        var topIdx = 0
        for i in 0..<searchEnd where smoothed[i] > smoothed[topIdx] { topIdx = i }
        let peak = smoothed[topIdx]

        let floorAfter = smoothed[topIdx...].min() ?? peak
        let floorBefore = smoothed[...topIdx].min() ?? peak
        guard peak > floorAfter, peak > floorBefore else { return fallback }

        let impactThreshold = floorAfter + (peak - floorAfter) * 0.4
        var impactIdx = n - 1
        for i in stride(from: n - 1, through: topIdx, by: -1) where smoothed[i] < impactThreshold {
            impactIdx = i
            break
        }
        let addressThreshold = floorBefore + (peak - floorBefore) * 0.4
        var addressIdx = 0
        for i in stride(from: topIdx, through: 0, by: -1) where smoothed[i] < addressThreshold {
            addressIdx = i
            break
        }
        guard impactIdx > topIdx, topIdx > addressIdx else { return fallback }
        return (times[addressIdx], times[impactIdx])
    }

    private static func movingAverage(_ x: [Double], halfWindow: Int) -> [Double] {
        let n = x.count
        guard n > 0 else { return [] }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - halfWindow), hi = min(n - 1, i + halfWindow)
            var sum = 0.0
            for k in lo...hi { sum += x[k] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    /// Best-fit swing plane from the grip path via PCA (least-variance direction of
    /// the whole hand path) — robust without needing checkpoint times, which this
    /// track doesn't carry.
    func fittedPlane() -> FittedPlane? {
        let pts = gripPath()
        guard pts.count > 8 else { return nil }
        let centroid = pts.reduce(SIMD3<Double>()) { $0 + $1 } / Double(pts.count)
        guard let normal = Self.planeNormalPCA(pts, centroid: centroid) else { return nil }
        let angle = Self.angleFromHorizontal(normal)
        let maxDist = pts.map { simd_length($0 - centroid) }.max() ?? 0.6
        return FittedPlane(normal: normal, point: centroid, angleDeg: angle, radius: max(maxDist * 1.2, 0.55))
    }

    /// Keep the fitted plane's data-derived azimuth but override the tilt magnitude
    /// with an externally supplied angle (e.g. the measurement pipeline's own
    /// `PlaneAnalysis.basePlaneAngle`).
    func reangled(_ fit: FittedPlane, toDeg angleDeg: Double) -> FittedPlane {
        let up = SIMD3<Double>(0, 1, 0)
        var horiz = fit.normal - up * simd_dot(fit.normal, up)
        if simd_length(horiz) < 1e-6 { horiz = SIMD3<Double>(1, 0, 0) }
        horiz = simd_normalize(horiz)
        let rad = angleDeg * .pi / 180
        var out = fit
        out.normal = simd_normalize(up * cos(rad) + horiz * sin(rad))
        out.angleDeg = angleDeg
        return out
    }

    /// Axis-aligned bounding box across the whole (grounded) track — used to
    /// auto-fit the default camera instead of guessing fixed numbers. Kept as a box
    /// rather than a sphere so the camera fit can reason about height vs. width
    /// separately (the harness card is much wider than tall).
    func boundingBox() -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        let fallback = (SIMD3<Double>(-0.4, 0, -0.4), SIMD3<Double>(0.4, 1.8, 0.4))
        guard !raw.isEmpty else { return fallback }
        var minP = SIMD3<Double>(1e9, 1e9, 1e9)
        var maxP = SIMD3<Double>(-1e9, -1e9, -1e9)
        var any = false
        for sample in raw {
            let ays = [sample[.ankleL]?.y, sample[.ankleR]?.y].compactMap { $0 }
            guard let ground = ays.min() else { continue }
            for (_, p) in sample {
                let g = SIMD3<Double>(p.x, p.y - ground, p.z)
                minP = simd_min(minP, g)
                maxP = simd_max(maxP, g)
                any = true
            }
        }
        guard any else { return fallback }
        return (minP, maxP)
    }

    // MARK: - Gap fill

    private static func fillGaps(_ frames: [[Joint: SIMD3<Double>]?], times: [Double]) -> [[Joint: SIMD3<Double>]] {
        var out = frames.map { $0 ?? [:] }
        for joint in Joint.allCases {
            var known: [(Int, SIMD3<Double>)] = []
            for (i, f) in frames.enumerated() {
                if let p = f?[joint] { known.append((i, p)) }
            }
            guard !known.isEmpty else { continue }
            for i in 0..<out.count where out[i][joint] == nil {
                let before = known.last(where: { $0.0 < i })
                let after = known.first(where: { $0.0 > i })
                switch (before, after) {
                case let (b?, a?):
                    let t0 = times[b.0], t1 = times[a.0]
                    let f = t1 > t0 ? (times[i] - t0) / (t1 - t0) : 0
                    out[i][joint] = b.1 + (a.1 - b.1) * f
                case let (b?, nil): out[i][joint] = b.1
                case let (nil, a?): out[i][joint] = a.1
                default: break
                }
            }
        }
        return out
    }

    // MARK: - Smoothing

    /// 5-tap binomial smoothing per joint per axis, reflected at the edges. Kills
    /// single-frame jitter (wrist confidence dips as low as ~0.18 in the fixture)
    /// while staying local enough (±80 ms) not to blur the downswing.
    private static func smoothed(_ dense: [[Joint: SIMD3<Double>]]) -> [[Joint: SIMD3<Double>]] {
        let n = dense.count
        guard n > 4 else { return dense }
        let kernel: [Double] = [1.0 / 16, 4.0 / 16, 6.0 / 16, 4.0 / 16, 1.0 / 16]
        var out = dense
        for joint in Joint.allCases {
            guard dense.contains(where: { $0[joint] != nil }) else { continue }
            for axis in 0..<3 {
                let x = (0..<n).map { dense[$0][joint]?[axis] ?? 0 }
                var y = [Double](repeating: 0, count: n)
                for i in 0..<n {
                    var acc = 0.0
                    for (k, w) in kernel.enumerated() {
                        var idx = i + k - 2
                        if idx < 0 { idx = -idx }
                        if idx >= n { idx = 2 * (n - 1) - idx }
                        idx = max(0, min(n - 1, idx))
                        acc += w * x[idx]
                    }
                    y[i] = acc
                }
                for i in 0..<n where out[i][joint] != nil { out[i][joint]![axis] = y[i] }
            }
        }
        return out
    }

    // MARK: - Grounding + interpolation

    private static func grounded(_ pose: [Joint: SIMD3<Double>]) -> [Joint: SIMD3<Double>] {
        let ay = [pose[.ankleL]?.y, pose[.ankleR]?.y].compactMap { $0 }
        guard let ground = ay.min() else { return pose }
        var out = pose
        for k in out.keys { out[k]!.y -= ground }
        return out
    }

    private static func catmullRom(_ p0: SIMD3<Double>, _ p1: SIMD3<Double>, _ p2: SIMD3<Double>,
                                    _ p3: SIMD3<Double>, _ t: Double) -> SIMD3<Double> {
        let t2: Double = t * t
        let t3: Double = t2 * t
        let a: SIMD3<Double> = 2 * p1
        let b: SIMD3<Double> = (p2 - p0) * t
        let c: SIMD3<Double> = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let d: SIMD3<Double> = (3 * p1 - p0 - 3 * p2 + p3) * t3
        let sum: SIMD3<Double> = a + b + c + d
        return sum * 0.5
    }

    // MARK: - Plane fit (PCA via deflated power iteration — a full Jacobi
    // eigensolver would work too, but for a one-shot 3×3 fit this is simpler to get
    // right, and just as exact).

    private static func angleFromHorizontal(_ normal: SIMD3<Double>) -> Double {
        let up = SIMD3<Double>(0, 1, 0)
        let c = min(1, max(-1, abs(simd_dot(simd_normalize(normal), up))))
        return acos(c) * 180 / .pi
    }

    private static func planeNormalPCA(_ points: [SIMD3<Double>], centroid: SIMD3<Double>) -> SIMD3<Double>? {
        var col0 = SIMD3<Double>(), col1 = SIMD3<Double>(), col2 = SIMD3<Double>()
        for p in points {
            let d = p - centroid
            col0 += d.x * d; col1 += d.y * d; col2 += d.z * d
        }
        let n = Double(points.count)
        let cov = simd_double3x3(columns: (col0 / n, col1 / n, col2 / n))

        let (v1, l1) = dominantEigenvector(of: cov, seed: SIMD3<Double>(0.4, 0.8, 0.3))
        guard l1 > 1e-9 else { return nil }
        let deflated = simd_double3x3(columns: (
            cov.columns.0 - l1 * v1.x * v1,
            cov.columns.1 - l1 * v1.y * v1,
            cov.columns.2 - l1 * v1.z * v1
        ))
        let (v2, _) = dominantEigenvector(of: deflated, seed: SIMD3<Double>(0.7, 0.1, 0.6))

        var normal = simd_cross(v1, v2)
        let len = simd_length(normal)
        guard len > 1e-9 else { return nil }
        normal /= len
        if normal.y < 0 { normal = -normal }
        return normal
    }

    private static func dominantEigenvector(of m: simd_double3x3, seed: SIMD3<Double>) -> (SIMD3<Double>, Double) {
        var v = simd_normalize(seed)
        for _ in 0..<50 {
            let mv = m * v
            let len = simd_length(mv)
            guard len > 1e-12 else { break }
            v = mv / len
        }
        let value = simd_dot(v, m * v)
        return (v, value)
    }
}
