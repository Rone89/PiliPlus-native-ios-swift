import AVFoundation
import SwiftUI

@main
struct PiliPlusNativeApp: App {
    @StateObject private var libraryStore: LibraryStore = .shared
    @StateObject private var authStore: AuthStore = .shared

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

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
