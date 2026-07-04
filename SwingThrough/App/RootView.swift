// App root: Home (gallery) → Analysis, with capture as a full-screen cover.
// Dev routing via env vars lets any surface be screenshot directly:
//   ST_SCREEN=avatar|capture|analysis, ST_POS=p1..p10, ST_SCROLL=metrics|bottom.
import SwiftUI
import SwingKit

struct RootView: View {
    @State private var path: [SwingRecord] = []
    @State private var showCapture = false

    @State private var demoAnalysis: AnalysisModel = {
        let demo = DemoData.load()
        return AnalysisModel(report: demo.report, videoURL: demo.videoURL, videoSize: demo.videoSize)
    }()

    var body: some View {
        let env = ProcessInfo.processInfo.environment
        switch env["ST_SCREEN"] {
        case "avatar": AvatarPreviewScreen()
        case "capture": CaptureScreen()
        case "analysis": AnalysisScreen(model: demoAnalysis)
        default:
            if env["ST_POS"] != nil || env["ST_SCROLL"] != nil {
                AnalysisScreen(model: demoAnalysis)
            } else {
                main
            }
        }
    }

    private var main: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                onRecord: { showCapture = true },
                onOpen: { path.append($0) }
            )
            .navigationDestination(for: SwingRecord.self) { record in
                if let model = SwingStore.analysisModel(for: record) {
                    AnalysisScreen(model: model, onBack: { path.removeLast() })
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureScreen(onCaptured: { url, view in
                // Analysis integration lands with the pipeline: analyze → save → open.
                _ = (url, view)
                showCapture = false
            })
        }
    }
}
