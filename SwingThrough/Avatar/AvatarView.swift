// Public entry point for the 3D swing avatar module.
import SwiftUI
import SwingKit

/// A second track rendered as a translucent, sand-grey ghost figure in the same
/// space as the primary — time-synced via a piecewise-linear warp between matched
/// checkpoint times, so two swings of different tempo move through the same swing
/// phase together (e.g. both at "top" simultaneously even if one gets there faster).
struct GhostTrack {
    var frames: [PoseFrame]
    var checkpoints: [Double]          // this track's own checkpoint times
    var primaryCheckpoints: [Double]   // the matching checkpoint times on the primary track
}

/// The 3D swing avatar: a sculpted clay mannequin animated from real 3D joint
/// tracks, with the swing-plane disc and grip-path ribbon overlays and an optional
/// ghost compare. Renders with a transparent background so the bone canvas shows
/// through underneath it.
struct AvatarView: View {
    let frames: [PoseFrame]
    @Binding var time: Double            // track-timeline seconds
    var isPlaying: Bool = false          // advances time via display link, writes back through binding
    var ghost: GhostTrack? = nil
    var planeAngle: Double? = nil
    var showPlane: Bool = true
    var showPath: Bool = true
    var orbitEnabled: Bool = true

    var body: some View {
        AvatarSceneView(frames: frames, time: $time, isPlaying: isPlaying, ghost: ghost,
                         planeAngle: planeAngle, showPlane: showPlane, showPath: showPath,
                         orbitEnabled: orbitEnabled)
            .background(Color.clear)
    }
}
