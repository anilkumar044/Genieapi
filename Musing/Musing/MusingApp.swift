import SwiftUI

@main
struct MusingApp: App {
    @State private var store = BoardStore()
    @State private var account = AccountStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .task { await account.verifyAppleCredential() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush pending edits whenever the app leaves the foreground.
            if phase != .active { store.save() }
        }
    }
}
