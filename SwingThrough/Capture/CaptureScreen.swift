// Capture flow entry. Reached via ST_SCREEN=capture (see RootView).
// The capture workstream replaces this placeholder.
import SwiftUI

struct CaptureScreen: View {
    var body: some View {
        ZStack {
            Color.bone.ignoresSafeArea()
            MicroLabel("Capture module — pending")
        }
    }
}
