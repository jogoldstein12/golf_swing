// Translucent scene dressing: the swing-plane disc, the tapered grip-path ribbon,
// the ground hairline, and a soft baked contact shadow. All unlit (`.constant` or
// flat-lit `.physicallyBased`) graphic elements, matching the reference prototype's
// MeshBasicMaterial approach for overlays vs. the figure's PBR clay.
import SceneKit
import UIKit
import simd

enum AvatarOverlays {

    // MARK: - Swing plane

    static func planeNode(fit: FittedPlane) -> SCNNode {
        let geo = SCNCylinder(radius: CGFloat(fit.radius), height: 0.002)
        geo.radialSegmentCount = 72
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = UIColor(red: 0xB4 / 255, green: 0xE0 / 255, blue: 0x19 / 255, alpha: 0.075)
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.simdPosition = SIMD3<Float>(fit.point)
        var n = SIMD3<Float>(fit.normal)
        if simd_length(n) < 1e-4 { n = SIMD3<Float>(0, 1, 0) }
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(n))
        node.renderingOrder = -5
        node.castsShadow = false
        return node
    }

    // MARK: - Grip path ribbon

    /// A tapered tube swept along the hands' full path — thicker near address/impact,
    /// tapering toward the top of the arc — with a small glow marker at the highest
    /// point (the top of backswing).
    static func pathNode(points: [SIMD3<Double>]) -> SCNNode {
        let node = SCNNode()
        guard points.count > 3 else { return node }
        let pts = points.map { SIMD3<Float>($0) }
        let topIdx = pts.indices.max(by: { pts[$0].y < pts[$1].y }) ?? 0
        let baseRadius: Float = 0.008

        let geo = tubeGeometry(along: pts, segments: 10) { i in
            let d = abs(Float(i - topIdx)) / Float(max(pts.count, 1))
            return baseRadius * (0.62 + 0.85 * min(d * 2.4, 1))
        }
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(red: 0x8F / 255, green: 0xB8 / 255, blue: 0x0F / 255, alpha: 1)
        mat.roughness.contents = 0.42
        mat.metalness.contents = 0.08
        geo.materials = [mat]
        node.geometry = geo

        let tipMat = SCNMaterial()
        tipMat.lightingModel = .constant
        tipMat.diffuse.contents = UIColor(red: 0xB4 / 255, green: 0xE0 / 255, blue: 0x19 / 255, alpha: 1)
        let tipGeo = SCNSphere(radius: CGFloat(baseRadius * 3.4))
        tipGeo.materials = [tipMat]
        let tip = SCNNode(geometry: tipGeo)
        tip.simdPosition = pts[topIdx]
        node.addChildNode(tip)
        return node
    }

    /// Minimal swept-tube mesh: a ring of `segments` points around each path sample,
    /// framed by a stable world-up reference (no twist correction needed — a swing
    /// arc doesn't invert on itself).
    private static func tubeGeometry(along path: [SIMD3<Float>], segments: Int,
                                      radiusAt: (Int) -> Float) -> SCNGeometry {
        let n = path.count
        guard n > 1 else { return SCNGeometry() }

        // Tangents by central difference.
        var tangents: [SIMD3<Float>] = []
        tangents.reserveCapacity(n)
        for i in 0..<n {
            let prev = path[max(0, i - 1)], next = path[min(n - 1, i + 1)]
            var t = next - prev
            if simd_length(t) < 1e-6 { t = tangents.last ?? SIMD3<Float>(0, 0, 1) }
            tangents.append(simd_normalize(t))
        }

        // Parallel-transport (rotation-minimizing) frame: each ring's basis is the
        // previous one rotated by the minimal rotation between consecutive tangents,
        // not referenced to a fixed world-up axis. A swing arc runs close to
        // vertical near the top, and a fixed-up reference flips sign right there —
        // this propagation has no such discontinuity.
        var rights: [SIMD3<Float>] = []
        var ups: [SIMD3<Float>] = []
        var right0 = simd_cross(SIMD3<Float>(0, 1, 0), tangents[0])
        if simd_length(right0) < 1e-3 { right0 = simd_cross(SIMD3<Float>(1, 0, 0), tangents[0]) }
        right0 = simd_normalize(right0)
        rights.append(right0)
        ups.append(simd_normalize(simd_cross(tangents[0], right0)))
        for i in 1..<n {
            let q = simd_quatf(from: tangents[i - 1], to: tangents[i])
            var r = q.act(rights[i - 1])
            r = r - tangents[i] * simd_dot(r, tangents[i])   // re-orthogonalize, kill drift
            if simd_length(r) < 1e-4 { r = rights[i - 1] }
            r = simd_normalize(r)
            rights.append(r)
            ups.append(simd_normalize(simd_cross(tangents[i], r)))
        }

        var rings: [[SIMD3<Float>]] = []
        rings.reserveCapacity(n)
        for i in 0..<n {
            let right = rights[i], up = ups[i]
            let r = radiusAt(i)
            var ring: [SIMD3<Float>] = []
            ring.reserveCapacity(segments)
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                ring.append(path[i] + right * (cos(a) * r) + up * (sin(a) * r))
            }
            rings.append(ring)
        }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        vertices.reserveCapacity(n * segments)
        normals.reserveCapacity(n * segments)
        for i in 0..<n {
            for s in 0..<segments {
                let p = rings[i][s]
                vertices.append(SCNVector3(p))
                normals.append(SCNVector3(simd_normalize(p - path[i])))
            }
        }
        var indices: [Int32] = []
        for i in 0..<(n - 1) {
            for s in 0..<segments {
                let sNext = (s + 1) % segments
                let a = Int32(i * segments + s), b = Int32(i * segments + sNext)
                let c = Int32((i + 1) * segments + s), d = Int32((i + 1) * segments + sNext)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let vSource = SCNGeometrySource(vertices: vertices)
        let nSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vSource, nSource], elements: [element])
    }

    // MARK: - Ground hairline

    static func groundRing(radius: Double) -> SCNNode {
        let geo = SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.0016)
        geo.ringSegmentCount = 96
        geo.pipeSegmentCount = 8
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = UIColor(white: 0.098, alpha: 0.16)
        mat.writesToDepthBuffer = false
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        node.renderingOrder = -8
        node.castsShadow = false
        return node
    }

    // MARK: - Baked contact shadow

    static func contactShadowNode(radius: Double) -> SCNNode {
        let size = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let colors = [UIColor.black.withAlphaComponent(0.30).cgColor,
                          UIColor.black.withAlphaComponent(0.0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                              endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        }
        let plane = SCNPlane(width: CGFloat(radius * 2), height: CGFloat(radius * 2))
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = image
        mat.writesToDepthBuffer = false
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.simdEulerAngles = SIMD3<Float>(-.pi / 2, 0, 0)
        node.renderingOrder = -9
        node.castsShadow = false
        return node
    }
}
