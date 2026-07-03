// Dev harness for the 3D avatar module. Reached via ST_SCREEN=avatar (see RootView).
// The avatar workstream replaces this placeholder.
import SwiftUI

struct AvatarPreviewScreen: View {
    var body: some View {
        ZStack {
            Color.bone.ignoresSafeArea()
            MicroLabel("Avatar module — pending")
        }
    }
}
