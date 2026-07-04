// Temporary design-foundation screen: proves fonts, tokens, shadows, and grain render
// correctly on device. Replaced by the real Home/Analysis flow in Phase 3.
import SwiftUI

struct RootView: View {
    @State private var analysis: AnalysisModel = {
        let demo = DemoData.load()
        return AnalysisModel(report: demo.report, videoURL: demo.videoURL, videoSize: demo.videoSize)
    }()

    var body: some View {
        // Dev routing: ST_SCREEN=avatar|capture jumps straight into a module harness
        // (simctl launch --setenv). Unset = the real app.
        switch ProcessInfo.processInfo.environment["ST_SCREEN"] {
        case "avatar": AvatarPreviewScreen()
        case "capture": CaptureScreen()
        default: AnalysisScreen(model: analysis)
        }
    }

    private var home: some View {
        ZStack {
            Color.bone.grain().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Top bar
                    HStack {
                        Text("Swing Through")
                            .font(Type.display(23))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        MicroLabel("Driver", color: .ink70)
                        Circle().fill(Color.ink).frame(width: 26, height: 26)
                    }

                    // Section heading
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("Swing Analysis")
                            (Text("Today, 7:42").foregroundStyle(Color.ink)
                                + Text(" am").foregroundStyle(Color.ink25))
                                .font(Type.display(34))
                        }
                        Spacer()
                        MicroLabel("03 · 07")
                    }
                    .padding(.top, 36)

                    FloatCard {
                        VStack(alignment: .leading, spacing: 14) {
                            MicroLabel("Design Foundation")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("86")
                                    .font(Type.display(72))
                                    .foregroundStyle(Color.ink)
                                Text("/100")
                                    .font(Type.display(24))
                                    .foregroundStyle(Color.ink25)
                            }
                            Text("Compact and powerful — the shaft steepens slightly at the top.")
                                .font(Type.displayItalic(19))
                                .foregroundStyle(Color.ink70)
                            Hairline()
                            HStack(spacing: 10) {
                                ForEach(
                                    [Color.bone, .sand, .ink, .fairway, .fairwayDeep, .brick, .amber],
                                    id: \.self
                                ) { c in
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(c)
                                        .frame(height: 34)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.ink08, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    .padding(.top, 20)

                    PrimaryButton("Record next swing") {}
                        .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    RootView()
}
