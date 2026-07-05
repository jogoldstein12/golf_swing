// The SceneKit host: builds the scene once (figure, ghost figure, lights, camera
// rig) and applies the AVPlayer-owned timeline. Scrubbing is instant
// (`updateUIView` re-applies the pose synchronously); SceneKit never owns a second
// playback clock.
import SceneKit
import SwiftUI
import SwingKit
import simd

/// `SCNView` subclass that reports real layout-driven size changes back to the
/// coordinator. `makeUIView` runs *before* SwiftUI lays the view out, so the very
/// first `fitCamera()` call (triggered as soon as data arrives) can see a zero-size
/// `bounds` and falls back to a guessed aspect ratio. This closure fires once the
/// view actually has a size — and again any time it's resized, e.g. hosted at a
/// different pane height (the Analysis screen's 400pt "3D" pane vs. its 176pt
/// "Split" pane) — so the camera fit always reflects the real aspect ratio.
final class AvatarHostView: SCNView {
    var onBoundsChange: ((CGSize) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onBoundsChange?(bounds.size)
    }
}

struct AvatarSceneView: UIViewRepresentable {
    let frames: [PoseFrame]
    @Binding var time: Double
    var isPlaying: Bool
    var ghost: GhostTrack?
    var planeAngle: Double?
    var showPlane: Bool
    var showPath: Bool
    var orbitEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(time: $time) }

    func makeUIView(context: Context) -> SCNView {
        let view = AvatarHostView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = ProcessInfo.processInfo.thermalState.rawValue >= 2 ? 20 : 30
        view.rendersContinuously = false
        view.scene = SCNScene()
        view.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        context.coordinator.panRecognizer = pan
        context.coordinator.pinchRecognizer = pinch

        context.coordinator.attach(to: view)
        let coordinator = context.coordinator
        view.onBoundsChange = { [weak coordinator] size in
            coordinator?.noteHostSize(size)
        }
        push(context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        push(context: context)
        view.rendersContinuously = isPlaying
        view.setNeedsDisplay()
    }

    private func push(context: Context) {
        context.coordinator.update(frames: frames, ghost: ghost, planeAngle: planeAngle)
        context.coordinator.setExternal(time: time, isPlaying: isPlaying, showPlane: showPlane,
                                         showPath: showPath, orbitEnabled: orbitEnabled)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private let timeBinding: Binding<Double>
        init(time: Binding<Double>) { self.timeBinding = time }

        private weak var scnView: SCNView?
        private let figure = AvatarFigureNode(isGhost: false)
        private let ghostFigure = AvatarFigureNode(isGhost: true)

        private var track: AvatarTrack?
        private var ghostTrack: AvatarTrack?
        private var ghostTimes: (primary: [Double], ghost: [Double])?
        private var trackFingerprint = Int.min
        private var ghostFingerprint = Int.min
        private var lastPlaneAngle: Double?
        private var planeAngleInitialized = false

        private var planeNode: SCNNode?
        private var pathNode: SCNNode?
        private var groundNode: SCNNode?
        private var shadowNode: SCNNode?

        // Orbit camera rig: rig (yaw, at target) -> pitch (elevation) -> camera (dolly).
        private let cameraRig = SCNNode()
        private let cameraPitch = SCNNode()
        private let cameraNode = SCNNode()
        private var azimuth: Float = 0.86
        private var elevation: Float = 0.20
        private var distance: Float = 3.0
        private var minDistance: Float = 1.8
        private var maxDistance: Float = 5.4

        var panRecognizer: UIPanGestureRecognizer?
        var pinchRecognizer: UIPinchGestureRecognizer?

        private var isPlayingFlag = false
        private var orbitEnabledFlag = true
        private var currentTime: Double = 0
        private var lastRenderTime: TimeInterval?

        /// The last real (non-zero) `SCNView` size we fitted the camera against —
        /// `.zero` until the first genuine layout pass lands. See `AvatarHostView`.
        private var lastHostSize: CGSize = .zero
        private var debugOrbitApplied = false

        func attach(to view: SCNView) {
            scnView = view
            guard let scene = view.scene else { return }
            buildLighting(in: scene.rootNode)
            scene.rootNode.addChildNode(figure.root)
            ghostFigure.root.isHidden = true
            scene.rootNode.addChildNode(ghostFigure.root)

            let camera = SCNCamera()
            camera.fieldOfView = 32
            camera.zNear = 0.05
            camera.zFar = 40
            cameraNode.camera = camera
            cameraPitch.addChildNode(cameraNode)
            cameraRig.addChildNode(cameraPitch)
            scene.rootNode.addChildNode(cameraRig)
            view.pointOfView = cameraNode
            updateCameraTransform()
        }

        // MARK: data

        func update(frames: [PoseFrame], ghost: GhostTrack?, planeAngle: Double?) {
            var needsOverlayRebuild = false

            let fp = Self.fingerprint(frames)
            if fp != trackFingerprint {
                trackFingerprint = fp
                track = AvatarTrack(frames: frames)
                fitCamera()
                needsOverlayRebuild = true
            }

            let gfp = ghost.map { Self.fingerprint($0.frames) } ?? Int.min
            if gfp != ghostFingerprint {
                ghostFingerprint = gfp
                if let ghost {
                    ghostTrack = AvatarTrack(frames: ghost.frames)
                    ghostTimes = (ghost.primaryCheckpoints, ghost.checkpoints)
                    ghostFigure.root.isHidden = false
                } else {
                    ghostTrack = nil
                    ghostTimes = nil
                    ghostFigure.root.isHidden = true
                }
            }

            if !planeAngleInitialized || lastPlaneAngle != planeAngle {
                lastPlaneAngle = planeAngle
                planeAngleInitialized = true
                needsOverlayRebuild = true
            }

            if needsOverlayRebuild { rebuildOverlays(planeAngle: planeAngle) }
            applyPose(at: currentTime)
        }

        private static func fingerprint(_ frames: [PoseFrame]) -> Int {
            var hasher = Hasher()
            hasher.combine(frames.count)
            hasher.combine(frames.first?.time ?? -1)
            hasher.combine(frames.last?.time ?? -1)
            return hasher.finalize()
        }

        func setExternal(time: Double, isPlaying: Bool, showPlane: Bool, showPath: Bool, orbitEnabled: Bool) {
            planeNode?.isHidden = !showPlane
            pathNode?.isHidden = !showPath
            orbitEnabledFlag = orbitEnabled
            panRecognizer?.isEnabled = orbitEnabled
            pinchRecognizer?.isEnabled = orbitEnabled

            if abs(time - currentTime) > 0.0004 {
                currentTime = time
                applyPose(at: time)
            } else {
                currentTime = time
            }
            isPlayingFlag = isPlaying
        }

        // MARK: pose application

        private func applyPose(at t: Double) {
            guard let track else { return }
            let pose = track.pose(at: t)
            if ProcessInfo.processInfo.environment["ST_DEBUG_POSE"] == "1" {
                var lines = "t=\(t)\n"
                for j in Joint.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
                    if let p = pose[j] { lines += "\(j.rawValue)=\(p)\n" }
                }
                let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("avatar_debug.log")
                try? lines.write(to: url, atomically: true, encoding: .utf8)
            }
            figure.apply(pose)
            updateGroundedExtras(pose: pose)
            if let ghostTrack, let ghostTimes, !ghostFigure.root.isHidden {
                let warped = Self.warp(t, primary: ghostTimes.primary, ghost: ghostTimes.ghost)
                ghostFigure.apply(ghostTrack.pose(at: warped))
            }
        }

        private func updateGroundedExtras(pose: [Joint: SIMD3<Double>]) {
            guard let l = pose[.ankleL], let r = pose[.ankleR] else { return }
            let c = (l + r) * 0.5
            let p = SIMD3<Float>(Float(c.x), 0, Float(c.z))
            groundNode?.simdPosition = p + SIMD3<Float>(0, 0.001, 0)
            shadowNode?.simdPosition = p + SIMD3<Float>(0, 0.0016, 0)
        }

        /// Piecewise-linear time warp between matched checkpoints, extrapolated
        /// linearly past the first/last pair.
        private static func warp(_ t: Double, primary: [Double], ghost: [Double]) -> Double {
            guard primary.count == ghost.count, primary.count >= 2 else { return t }
            let n = primary.count
            if t <= primary[0] {
                let span = max(primary[1] - primary[0], 1e-6)
                return ghost[0] + (t - primary[0]) / span * (ghost[1] - ghost[0])
            }
            for i in 0..<(n - 1) where t <= primary[i + 1] {
                let span = max(primary[i + 1] - primary[i], 1e-6)
                return ghost[i] + (t - primary[i]) / span * (ghost[i + 1] - ghost[i])
            }
            let span = max(primary[n - 1] - primary[n - 2], 1e-6)
            return ghost[n - 2] + (t - primary[n - 2]) / span * (ghost[n - 1] - ghost[n - 2])
        }

        // MARK: overlays

        private func rebuildOverlays(planeAngle: Double?) {
            guard let track, let scene = scnView?.scene else { return }
            planeNode?.removeFromParentNode()
            pathNode?.removeFromParentNode()
            groundNode?.removeFromParentNode()
            shadowNode?.removeFromParentNode()

            let path = track.downswingPath()
            var groundRadius = 0.85
            if var fit = track.fittedPlane() {
                if let angleDeg = planeAngle { fit = track.reangled(fit, toDeg: angleDeg) }
                let plane = AvatarOverlays.planeNode(fit: fit)
                scene.rootNode.addChildNode(plane)
                planeNode = plane
                groundRadius = max(fit.radius * 0.6, 0.55)
            }

            let ribbon = AvatarOverlays.pathNode(points: path)
            scene.rootNode.addChildNode(ribbon)
            pathNode = ribbon

            let ring = AvatarOverlays.groundRing(radius: groundRadius)
            scene.rootNode.addChildNode(ring)
            groundNode = ring

            let shadow = AvatarOverlays.contactShadowNode(radius: groundRadius * 0.82)
            scene.rootNode.addChildNode(shadow)
            shadowNode = shadow
        }

        // MARK: camera

        /// Called by `AvatarHostView.onBoundsChange` whenever the SCNView's real
        /// layout size lands or changes (initial layout, rotation, or the host
        /// resizing the pane, e.g. Analysis screen's 400pt "3D" ⇄ 176pt "Split").
        /// `fitCamera()` reads `scnView.bounds` directly, so this just needs to
        /// re-trigger it at the right moments — including the very first one, which
        /// `update(frames:)` alone can't guarantee since it may run before SwiftUI
        /// has ever laid the view out (bounds still `.zero` then).
        func noteHostSize(_ size: CGSize) {
            guard size.width > 1, size.height > 1 else { return }
            guard abs(size.width - lastHostSize.width) > 0.5 || abs(size.height - lastHostSize.height) > 0.5 else { return }
            lastHostSize = size
            fitCamera()
        }

        private func fitCamera() {
            guard let track else { return }
            let (minP, maxP) = track.boundingBox()
            let center = (minP + maxP) * 0.5
            let halfHeight = max((maxP.y - minP.y) * 0.5, 0.3)
            let halfWidth = max((maxP.x - minP.x) * 0.5, (maxP.z - minP.z) * 0.5, 0.25)

            let fovRad: Float = 32 * .pi / 180
            let aspect: Float = {
                guard let size = scnView?.bounds.size, size.height > 0 else { return 1.6 }
                return Float(size.width / size.height)
            }()
            let horizFovRad = 2 * atan(tan(fovRad / 2) * aspect)
            let distV = Float(halfHeight) / tan(fovRad / 2)
            let distH = Float(halfWidth) / tan(horizFovRad / 2)
            let fit = max(distV, distH) * 1.16

            distance = fit
            minDistance = fit * 0.6
            maxDistance = fit * 1.85
            cameraRig.simdPosition = SIMD3<Float>(center)
            updateCameraTransform()
            applyDebugOrbitIfNeeded()
        }

        /// Test-only hook so orbit/pinch can be exercised deterministically without
        /// synthetic touch input: nudges the same `azimuth`/`elevation`/`distance`
        /// state the real gesture handlers drive, through the same clamped math, once
        /// the camera has a real fit to nudge from. No-op unless `ST_ORBIT_DX`,
        /// `ST_ORBIT_DY`, or `ST_ZOOM` is set (mirrors the `ST_DEBUG_POSE` /
        /// `AvatarPreviewScreen` `ST_*` dev-hook convention).
        private func applyDebugOrbitIfNeeded() {
            guard !debugOrbitApplied, lastHostSize.width > 1, lastHostSize.height > 1 else { return }
            let env = ProcessInfo.processInfo.environment
            guard env["ST_ORBIT_DX"] != nil || env["ST_ORBIT_DY"] != nil || env["ST_ZOOM"] != nil else { return }
            debugOrbitApplied = true
            let dx = Float(env["ST_ORBIT_DX"].flatMap(Double.init) ?? 0)
            let dy = Float(env["ST_ORBIT_DY"].flatMap(Double.init) ?? 0)
            let zoom = Float(env["ST_ZOOM"].flatMap(Double.init) ?? 1)
            azimuth -= dx * 0.0055
            elevation = max(-0.1, min(0.92, elevation + dy * 0.0055))
            if zoom != 1 { distance = max(minDistance, min(maxDistance, distance / zoom)) }
            updateCameraTransform()
        }

        private func updateCameraTransform() {
            cameraRig.simdEulerAngles = SIMD3<Float>(0, azimuth, 0)
            cameraPitch.simdEulerAngles = SIMD3<Float>(-elevation, 0, 0)
            cameraNode.simdPosition = SIMD3<Float>(0, 0, distance)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard orbitEnabledFlag, let v = g.view else { return }
            guard g.state == .changed else { return }
            let t = g.translation(in: v)
            azimuth -= Float(t.x) * 0.0055
            elevation = max(-0.1, min(0.92, elevation + Float(t.y) * 0.0055))
            updateCameraTransform()
            g.setTranslation(.zero, in: v)
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard orbitEnabledFlag, g.state == .changed else { return }
            distance = max(minDistance, min(maxDistance, distance / Float(g.scale)))
            updateCameraTransform()
            g.scale = 1
        }

        // MARK: lighting — soft studio three-point + a warm rim so the clay reads
        // against the bone canvas without a shader-level fresnel hack.

        private func buildLighting(in root: SCNNode) {
            // A pure-white key + a fairly hot ambient fill were washing the clay's
            // warm #AA9A7E out toward pale gray. Warming the key slightly and
            // trimming the ambient contribution lets the material's own warmth read
            // through in the actual render, not just in the material property.
            let key = SCNLight()
            key.type = .directional
            key.intensity = 1080
            key.color = UIColor(red: 1, green: 0.965, blue: 0.905, alpha: 1)
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.simdEulerAngles = SIMD3<Float>(-.pi / 3.3, .pi / 6, 0)
            root.addChildNode(keyNode)

            let fill = SCNLight()
            fill.type = .directional
            fill.intensity = 340
            fill.color = UIColor(red: 1, green: 0.965, blue: 0.88, alpha: 1)
            let fillNode = SCNNode()
            fillNode.light = fill
            fillNode.simdEulerAngles = SIMD3<Float>(-.pi / 9, -.pi / 2.2, 0)
            root.addChildNode(fillNode)

            // Subtle fresnel-style rim: a warm grazing light that catches the
            // silhouette edge so the clay separates from the paper card without a
            // shader-level fresnel term.
            let rim = SCNLight()
            rim.type = .directional
            rim.intensity = 660
            rim.color = UIColor(red: 0.99, green: 0.93, blue: 0.8, alpha: 1)
            let rimNode = SCNNode()
            rimNode.light = rim
            rimNode.simdEulerAngles = SIMD3<Float>(-.pi / 8, .pi * 0.94, 0)
            root.addChildNode(rimNode)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 205
            ambient.color = UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1)
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            root.addChildNode(ambientNode)
        }

        // MARK: SCNSceneRendererDelegate

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // AVPlayer's periodic observer is the only playback clock. Rendering
            // remains continuous only while visible and playing.
        }
    }
}
