import SwiftUI

@main
struct PiliPlusNativeApp: App {
    @StateObject private var libraryStore: LibraryStore = .shared
    @StateObject private var authStore: AuthStore = .shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(libraryStore)
                .environmentObject(authStore)
                .task {
                    await authStore.syncIfNeeded()
                }
        }
    }
}
