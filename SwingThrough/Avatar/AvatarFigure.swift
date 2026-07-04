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
    private let faceNode = SCNNode()
    private let handL = SCNNode()
    private let handR = SCNNode()
    private let handLength: Double = 0.095

    init(isGhost: Bool) {
        bones = Self.boneTable()
        build(isGhost: isGhost)
    }

    private static func boneTable() -> [BoneSpec] {
        // (joint, joint, radius in meters) — thick at the pelvis/torso so it reads as
        // mass, tapering out through the limbs; joint spheres (below) are sized from
        // the thickest bone they touch so every union looks fused, not stick-figure.
        let table: [(Joint, Joint, Double)] = [
            (.ankleL, .kneeL, 0.045), (.kneeL, .hipL, 0.058),
            (.ankleR, .kneeR, 0.045), (.kneeR, .hipR, 0.058),
            (.hipL, .pelvis, 0.068), (.hipR, .pelvis, 0.068), (.hipL, .hipR, 0.06),
            (.pelvis, .spine, 0.088), (.spine, .neck, 0.074),
            (.neck, .shoulderL, 0.03), (.neck, .shoulderR, 0.03),
            (.shoulderL, .shoulderR, 0.05),
            (.shoulderL, .elbowL, 0.04), (.elbowL, .wristL, 0.032),
            (.shoulderR, .elbowR, 0.04), (.elbowR, .wristR, 0.032),
            (.neck, .head, 0.03),
        ]
        return table.map { BoneSpec(a: $0.0, b: $0.1, radius: $0.2) }
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
            let bump = joint == .pelvis ? 1.14 : 1.16
            let geo = SCNSphere(radius: CGFloat(rad * bump))
            geo.segmentCount = 20
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.categoryBitMask = 1
            root.addChildNode(node)
            jointNodes[joint] = node
        }

        let headGeo = SCNSphere(radius: 0.1)
        headGeo.segmentCount = 28
        headGeo.materials = [mat]
        headNode.geometry = headGeo
        headNode.categoryBitMask = 1
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
