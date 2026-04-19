import SwiftUI

@main
struct PiliPlusNativeApp: App {
    @StateObject private var libraryStore: LibraryStore = .shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(libraryStore)
        }
    }
}
