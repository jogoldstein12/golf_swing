// The skeletal vocabulary shared by the whole app: capture, measurement, overlays, avatar.
// Mirrors Vision's 17-joint 3D body (VNHumanBodyPose3DObservation) with stable string keys
// so tracks serialize cleanly and fixtures are human-readable.
import Foundation
import simd

public enum Joint: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case topHead, head, neck, spine, pelvis
    case shoulderL, shoulderR, elbowL, elbowR, wristL, wristR
    case hipL, hipR, kneeL, kneeR, ankleL, ankleR
}

public enum Bones {
    /// Connectivity used for skeleton rendering (2D overlay and 3D avatar share it).
    public static let all: [(Joint, Joint)] = [
        (.ankleL, .kneeL), (.kneeL, .hipL), (.ankleR, .kneeR), (.kneeR, .hipR),
        (.hipL, .pelvis), (.hipR, .pelvis), (.hipL, .hipR),
        (.pelvis, .spine), (.spine, .neck),
        (.neck, .shoulderL), (.neck, .shoulderR), (.shoulderL, .shoulderR),
        (.shoulderL, .elbowL), (.elbowL, .wristL),
        (.shoulderR, .elbowR), (.elbowR, .wristR),
        (.neck, .head), (.head, .topHead),
    ]
}

/// One tracked frame. 3D joints are in Vision's model space (meters, subject-local,
/// +y up); 2D joints are normalized image coordinates with origin at top-left, y down —
/// ready to scale straight into an overlay.
public struct PoseFrame: Codable, Sendable {
    public var time: Double
    public var j3: [Joint: SIMD3<Double>]
    public var j2: [Joint: SIMD2<Double>]
    public var confidence: [Joint: Double]

    public init(time: Double,
                j3: [Joint: SIMD3<Double>] = [:],
                j2: [Joint: SIMD2<Double>] = [:],
                confidence: [Joint: Double] = [:]) {
        self.time = time
        self.j3 = j3
        self.j2 = j2
        self.confidence = confidence
    }

    /// Grip proxy: midpoint of the wrists. The club is not a tracked joint; all
    /// plane/path math anchors on this.
    public var grip3: SIMD3<Double>? {
        guard let l = j3[.wristL], let r = j3[.wristR] else { return j3[.wristL] ?? j3[.wristR] }
        return (l + r) * 0.5
    }
    public var grip2: SIMD2<Double>? {
        guard let l = j2[.wristL], let r = j2[.wristR] else { return j2[.wristL] ?? j2[.wristR] }
        return (l + r) * 0.5
    }
}
