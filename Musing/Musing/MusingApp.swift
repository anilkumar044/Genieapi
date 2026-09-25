import SwiftUI

@main
struct MusingApp: App {
    @State private var store = BoardStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush pending edits whenever the app leaves the foreground.
            if phase != .active { store.save() }
        }
    }
}
