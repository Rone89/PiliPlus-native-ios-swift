import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                VideoFeedView(kind: .recommend)
            }
            .tabItem {
                Label("推荐", systemImage: "sparkles.tv")
            }

            NavigationStack {
                VideoFeedView(kind: .popular)
            }
            .tabItem {
                Label("热门", systemImage: "flame")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(AppTheme.accent)
    }
}

