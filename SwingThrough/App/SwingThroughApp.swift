import SwiftData
import SwiftUI

@main
struct SwingThroughApp: App {
    private let modelContainer: ModelContainer?
    private let persistenceWarning: String?

    init() {
        do {
            modelContainer = try ModelContainer(for: SwingRecord.self)
            persistenceWarning = nil
        } catch {
            // A damaged or incompatible on-device store must not make the app
            // unlaunchable. The in-memory fallback keeps capture/analysis usable and
            // makes the persistence limitation visible in RootView.
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            modelContainer = try? ModelContainer(for: SwingRecord.self, configurations: fallback)
            persistenceWarning = "History could not be opened. Swings will not be saved after this launch."
            NSLog("SwingThrough: persistent store unavailable: %@", error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootView(startupWarning: persistenceWarning)
                    .modelContainer(modelContainer)
                    .preferredColorScheme(.light)
            } else {
                StartupFailureView()
                    .preferredColorScheme(.light)
            }
        }
    }
}

private struct StartupFailureView: View {
    var body: some View {
        ZStack {
            Color.bone.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("Swing Through").font(Type.display(28))
                Text("The local data store could not be created.")
                    .font(Type.display(22))
                Text("Restart the app. If this continues, delete and reinstall this development build.")
                    .font(Type.ui(14))
                    .foregroundStyle(Color.ink70)
            }
            .padding(28)
        }
    }
}
