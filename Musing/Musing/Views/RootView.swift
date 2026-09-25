import SwiftUI

/// Hosts the board hierarchy. Opening a board card pushes it with a zoom transition.
struct RootView: View {
    @Environment(BoardStore.self) private var store
    @State private var path: [UUID] = []
    @Namespace private var zoomNamespace

    var body: some View {
        NavigationStack(path: $path) {
            BoardScreen(boardID: store.rootID, path: $path, zoomNamespace: zoomNamespace)
                .navigationDestination(for: UUID.self) { boardID in
                    BoardScreen(boardID: boardID, path: $path, zoomNamespace: zoomNamespace)
                        .navigationTransition(.zoom(sourceID: boardID, in: zoomNamespace))
                }
        }
    }
}
