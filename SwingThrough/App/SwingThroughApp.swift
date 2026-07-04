import SwiftData
import SwiftUI

@main
struct SwingThroughApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(for: SwingRecord.self)
    }
}
