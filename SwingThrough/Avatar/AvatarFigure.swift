// The sculpted mannequin: a persistent SceneKit node graph (capsule bones + joint
// spheres + head + mitt hands + a subtle face-plane cue) built once, then driven
// every frame by `apply(_:)` setting node transforms — no per-frame geometry churn.
// Proportions and per-segment radii are a from-scratch sculptural pass, taking the
// web prototype's `boneRadius` table (reference/src/data/swing.ts) as a starting
// point and adapting it to this app's joint set (a `spine` joint instead of a
// `chest` joint; the connectivity comes from SwingKit's own `Bones.all`).
import SceneKit
import SwingKit
import UIKit
import simd

extension SCNVector3 {
    init(_ v: SIMD3<Float>) { self.init(v.x, v.y, v.z) }
}

final class AvatarFigureNode {
    let root = SCNNode()

    private struct BoneSpec { let a: Joint; let b: Joint; let radius: Double }
    private let bones: [BoneSpec]
    private var boneNodes: [SCNNode] = []
    private var jointNodes: [Joint: SCNNode] = [:]

    private let headNode = SCNNode()
    private let headShapeNode = SCNNode()
    private let faceNode = SCNNode()
    private let handL = SCNNode()
    private let handR = SCNNode()
    private let handLength: Double = 0.095
    private let footL = SCNNode()
    private let footR = SCNNode()
    private let footLength: Double = 0.15
    private let footRadius: Double = 0.034
    // Sculpted torso mass: two oblate "blob" volumes layered over the pelvis→spine
    // and spine→neck core capsules — pelvis bulk low, ribcage bulk high, with the
    // core capsule's own (now narrower) radius reading as the waist in between.
    private let pelvisMass = SCNNode()
    private let ribMass = SCNNode()

    init(isGhost: Bool) {
        bones = Self.boneTable()
        build(isGhost: isGhost)
    }

    private static func boneTable() -> [BoneSpec] {
        // (joint, joint, radius in meters) — thick at the pelvis/torso so it reads as
        // mass, tapering out through the limbs; joint spheres (below) are sized per-
        // category (see `jointBump`) so extremity joints (elbow/knee/wrist/ankle)
        // read as smoothing fillets while shoulders/hips/spine stay blended as mass.
        // The pelvis/spine/neck core radii are deliberately narrower than before —
        // sculpted bulk there now comes from `pelvisMass`/`ribMass` layered on top,
        // so the bare core reads as a waist, not a plain wide tube.
        let table: [(Joint, Joint, Double)] = [
            (.ankleL, .kneeL, 0.045), (.kneeL, .hipL, 0.058),
            (.ankleR, .kneeR, 0.045), (.kneeR, .hipR, 0.058),
            (.hipL, .pelvis, 0.068), (.hipR, .pelvis, 0.068), (.hipL, .hipR, 0.06),
            (.pelvis, .spine, 0.076), (.spine, .neck, 0.062),
            (.neck, .shoulderL, 0.03), (.neck, .shoulderR, 0.03),
            (.shoulderL, .shoulderR, 0.05),
            (.shoulderL, .elbowL, 0.04), (.elbowL, .wristL, 0.032),
            (.shoulderR, .elbowR, 0.04), (.elbowR, .wristR, 0.032),
            (.neck, .head, 0.036),
        ]
        return table.map { BoneSpec(a: $0.0, b: $0.1, radius: $0.2) }
    }

    /// Joint-sphere bump factor, as a fraction of the thickest bone touching that
    /// joint. Extremity hinge joints (elbow/knee/wrist/ankle) get only a hair more
    /// than the limb itself — a smoothing fillet, not a feature. Shoulders/hips and
    /// the spine/neck/pelvis blend a bit more generously since they're carrying
    /// torso mass, not a hinge.
    private static func jointBump(_ joint: Joint) -> Double {
        switch joint {
        case .elbowL, .elbowR, .kneeL, .kneeR, .wristL, .wristR, .ankleL, .ankleR:
            return 1.05
        case .pelvis:
            return 1.1
        default:
            return 1.16
        }
    }

    private func makeMaterial(isGhost: Bool, darker: Bool = false) -> SCNMaterial {
        let clay = UIColor(red: 0xAA / 255, green: 0x9A / 255, blue: 0x7E / 255, alpha: 1)
        let clayFace = UIColor(red: 0x93 / 255, green: 0x84 / 255, blue: 0x6B / 255, alpha: 1)
        // Distinct mid-tone, not the DesignSystem `.sand` canvas token — that pale a
        // grey would nearly vanish at 35% opacity against the bone canvas.
        let ghost = UIColor(red: 0x9E / 255, green: 0x94 / 255, blue: 0x82 / 255, alpha: 1)
        let ghostFace = UIColor(red: 0x8A / 255, green: 0x80 / 255, blue: 0x70 / 255, alpha: 1)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = isGhost ? (darker ? ghostFace : ghost) : (darker ? clayFace : clay)
        m.roughness.contents = darker ? 0.86 : 0.76
        m.metalness.contents = 0.03
        if isGhost {
            m.transparency = 0.35
            m.writesToDepthBuffer = false
        }
        return m
    }

    private func build(isGhost: Bool) {
        let mat = makeMaterial(isGhost: isGhost)

        for spec in bones {
            let geo = SCNCapsule(capRadius: CGFloat(spec.radius), height: 1)
            geo.radialSegmentCount = 16
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.categoryBitMask = 1
            root.addChildNode(node)
            boneNodes.append(node)
        }

        var jointRadius: [Joint: Double] = [:]
        for spec in bones {
            jointRadius[spec.a] = max(jointRadius[spec.a] ?? 0, spec.radius)
            jointRadius[spec.b] = max(jointRadius[spec.b] ?? 0, spec.radius)
        }
        for (joint, rad) in jointRadius {
            let bump = Self.jointBump(joint)
            let geo = SCNSphere(radius: CGFloat(rad * bump))
            geo.segmentCount = 20
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.categoryBitMask = 1
            root.addChildNode(node)
            jointNodes[joint] = node
        }

        // Egg-shaped head: the sphere geometry lives on a child node so its y-scale
        // (the "egg") doesn't also stretch `faceNode`, which stays a plain sibling
        // at the same front-facing offset used before.
        let headGeo = SCNSphere(radius: 0.1)
        headGeo.segmentCount = 28
        headGeo.materials = [mat]
        headShapeNode.geometry = headGeo
        headShapeNode.simdScale = SIMD3<Float>(1, 1.12, 1)
        headShapeNode.categoryBitMask = 1
        headNode.addChildNode(headShapeNode)
        root.addChildNode(headNode)

        let faceMat = makeMaterial(isGhost: isGhost, darker: true)
        let faceGeo = SCNBox(width: 0.072, height: 0.05, length: 0.01, chamferRadius: 0.018)
        faceGeo.materials = [faceMat]
        faceNode.geometry = faceGeo
        faceNode.position = SCNVector3(0, 0.004, 0.088)
        headNode.addChildNode(faceNode)

        for hand in [handL, handR] {
            let geo = SCNCapsule(capRadius: 0.05, height: 1)
            geo.radialSegmentCount = 14
            geo.materials = [mat]
            hand.geometry = geo
            hand.categoryBitMask = 1
            root.addChildNode(hand)
        }

        for foot in [footL, footR] {
            let geo = SCNCapsule(capRadius: CGFloat(footRadius), height: 1)
            geo.radialSegmentCount = 14
            geo.materials = [mat]
            foot.geometry = geo
            foot.categoryBitMask = 1
            root.addChildNode(foot)
        }

        // Sculpted torso masses: oblate blobs (spheres squashed flat along the
        // spine's own length) layered over the pelvis→spine and spine→neck core
        // capsules — pelvis bulk low, ribcage bulk high, waist reads in between
        // from the thinner core alone. Positioned/oriented every frame in `apply`.
        for (node, radiusXZ, radiusY) in [(pelvisMass, 0.1, 0.084), (ribMass, 0.096, 0.078)] {
            let geo = SCNSphere(radius: 1)
            geo.segmentCount = 22
            geo.materials = [mat]
            node.geometry = geo
            node.simdScale = SIMD3<Float>(Float(radiusXZ), Float(radiusY), Float(radiusXZ))
            node.categoryBitMask = 1
            root.addChildNode(node)
        }
    }

    /// Update every node transform from a grounded pose (meters, +y up). A joint
    /// missing from the pose leaves its node at its last transform rather than
    /// popping it away — with gap-fill upstream this only happens off both track
    /// ends, never mid-swing.
    func apply(_ pose: [Joint: SIMD3<Double>]) {
        for (i, spec) in bones.enumerated() {
            guard let a = pose[spec.a], let b = pose[spec.b] else { continue }
            place(boneNodes[i], from: a, to: b)
        }
        for (joint, node) in jointNodes {
            guard let p = pose[joint] else { continue }
            node.simdPosition = SIMD3<Float>(p)
        }
        if let head = pose[.head] {
            headNode.simdPosition = SIMD3<Float>(head)
            let up = pose[.topHead].map { $0 - head } ?? SIMD3<Double>(0, 0.12, 0)
            headNode.simdOrientation = Self.headBasis(up: up)
        }
        placeHand(handL, wrist: pose[.wristL], elbow: pose[.elbowL])
        placeHand(handR, wrist: pose[.wristR], elbow: pose[.elbowR])
        placeFoot(footL, ankle: pose[.ankleL])
        placeFoot(footR, ankle: pose[.ankleR])
        if let pelvis = pose[.pelvis], let spine = pose[.spine] {
            placeMass(pelvisMass, from: pelvis, to: spine, fraction: 0.32)
        }
        if let spine = pose[.spine], let neck = pose[.neck] {
            placeMass(ribMass, from: spine, to: neck, fraction: 0.58)
        }
    }

    private func place(_ node: SCNNode, from a: SIMD3<Double>, to b: SIMD3<Double>) {
        let af = SIMD3<Float>(a), bf = SIMD3<Float>(b)
        let d = bf - af
        let len = simd_length(d)
        guard len > 0.0004 else { node.isHidden = true; return }
        node.isHidden = false
        node.simdPosition = (af + bf) * 0.5
        node.simdScale = SIMD3<Float>(1, len, 1)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: d / len)
    }

    private func placeHand(_ node: SCNNode, wrist: SIMD3<Double>?, elbow: SIMD3<Double>?) {
        guard let wrist, let elbow else { return }
        let dir = simd_normalize(wrist - elbow)
        let tip = wrist + dir * handLength
        place(node, from: wrist, to: tip)
    }

    /// A stylized foot: a short capsule from the tracked ankle forward to a toe
    /// that's clamped to (near) the ground plane. Vision carries no foot/toe joint,
    /// and the body-local pose space (see AvatarTrack's coordinate note) can leave
    /// one ankle sitting a few centimeters above the other even in a level, planted
    /// stance — clamping the toe, not the ankle, plants both feet convincingly on
    /// the ground reference without touching the tracked leg's own bone lengths.
    private func placeFoot(_ node: SCNNode, ankle: SIMD3<Double>?) {
        guard let ankle else { return }
        let forward = SIMD3<Double>(0, 0, 1)
        var toe = ankle + forward * footLength
        toe.y = min(ankle.y, 0.006)
        place(node, from: ankle, to: toe)
    }

    /// Positions/orients a fixed-shape oblate "mass" node at a fraction along a
    /// joint-to-joint segment, its short (squashed) axis kept aligned with the
    /// segment direction so it reads as a cross-sectional bulge, not a stray ball.
    /// Scale is set once at build time and never touched here.
    private func placeMass(_ node: SCNNode, from a: SIMD3<Double>, to b: SIMD3<Double>, fraction: Double) {
        let af = SIMD3<Float>(a), bf = SIMD3<Float>(b)
        let d = bf - af
        let len = simd_length(d)
        guard len > 0.0004 else { node.isHidden = true; return }
        node.isHidden = false
        node.simdPosition = af + d * Float(fraction)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: d / len)
    }

    /// A twist-consistent basis for the head: `up` follows the real neck→topHead
    /// tilt every frame; `front` is a fixed reference direction (this pose space's
    /// empirical "front", per the coordinate note in AvatarTrack) projected flat
    /// against the current up so it never free-spins.
    private static func headBasis(up rawUp: SIMD3<Double>) -> simd_quatf {
        var up = SIMD3<Float>(rawUp)
        if simd_length(up) < 1e-4 { up = SIMD3<Float>(0, 1, 0) }
        up = simd_normalize(up)
        var front = SIMD3<Float>(0, 0, 1)
        front -= up * simd_dot(front, up)
        if simd_length(front) < 1e-3 { front = SIMD3<Float>(1, 0, 0) - up * simd_dot(SIMD3<Float>(1, 0, 0), up) }
        front = simd_normalize(front)
        let right = simd_normalize(simd_cross(up, front))
        return simd_quatf(simd_float3x3(columns: (right, up, front)))
    }
}
