import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        TabView {
            NavigationStack {
                HomeHubView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }

            NavigationStack {
                DynamicFeedView()
            }
            .tabItem {
                Label("动态", systemImage: "dot.radiowaves.left.and.right")
            }
            .badge(authStore.unreadState.dynamicUnread == 0 ? nil : authStore.unreadState.dynamicUnread)

            NavigationStack {
                MessagesView()
            }
            .tabItem {
                Label("私信", systemImage: "bubble.left.and.bubble.right")
            }
            .badge(authStore.unreadState.privateUnread == 0 ? nil : authStore.unreadState.privateUnread)

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("搜索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("我的", systemImage: "person.crop.circle")
            }
        }
        .tint(AppTheme.accent)
    }
}
