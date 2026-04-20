import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var showClearHistoryConfirmation = false
    @State private var showClearFavoritesConfirmation = false
    @State private var showLoginSheet = false

    var body: some View {
        List {
            accountSection

            if !libraryStore.history.isEmpty {
                Section("继续观看") {
                    ForEach(libraryStore.history) { record in
                        NavigationLink {
                            VideoDetailView(bvid: record.video.bvid, aid: record.video.aid)
                        } label: {
                            WatchHistoryRow(record: record)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                libraryStore.removeHistory(bvid: record.video.bvid)
                            } label: {
                                Label("删除历史", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !libraryStore.favorites.isEmpty {
                Section("本地收藏") {
                    ForEach(libraryStore.favorites) { video in
                        NavigationLink {
                            VideoDetailView(bvid: video.bvid, aid: video.aid)
                        } label: {
                            FavoriteRow(video: video)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                libraryStore.removeFavorite(bvid: video.bvid)
                            } label: {
                                Label("移除收藏", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }

            Section("更多") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !libraryStore.history.isEmpty {
                        Button(role: .destructive) {
                            showClearHistoryConfirmation = true
                        } label: {
                            Label("清空历史", systemImage: "clock.arrow.circlepath")
                        }
                    }

                    if !libraryStore.favorites.isEmpty {
                        Button(role: .destructive) {
                            showClearFavoritesConfirmation = true
                        } label: {
                            Label("清空收藏", systemImage: "star.slash")
                        }
                    }

                    if authStore.isLoggedIn {
                        Button(role: .destructive) {
                            Task {
                                await authStore.logout()
                            }
                        } label: {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("确认清空全部历史记录？", isPresented: $showClearHistoryConfirmation) {
            Button("清空历史", role: .destructive) {
                libraryStore.clearHistory()
            }
        }
        .confirmationDialog("确认清空全部本地收藏？", isPresented: $showClearFavoritesConfirmation) {
            Button("清空收藏", role: .destructive) {
                libraryStore.clearFavorites()
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .environmentObject(authStore)
        }
        .refreshable {
            await authStore.sync()
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section(authStore.isLoggedIn ? "账号" : "游客模式") {
            if authStore.isLoggedIn {
                if let user = authStore.currentUser {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            AsyncImage(url: user.faceURL) { phase in
                                switch phase {
                                case let .success(image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Circle().fill(.quaternary)
                                case .empty:
                                    Circle().fill(.quaternary).overlay(ProgressView())
                                @unknown default:
                                    Circle().fill(.quaternary)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 8) {
                                Text(user.name)
                                    .font(.title3.bold())

                                Text("UID \(user.mid)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    if let levelText = user.levelText {
                                        Label(levelText, systemImage: "star.circle")
                                    }
                                    if let coinsText = user.coinsText {
                                        Label(coinsText, systemImage: "bitcoinsign.circle")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            if let following = user.followingText {
                                Label(following, systemImage: "person.badge.plus")
                            }
                            if let followers = user.followersText {
                                Label(followers, systemImage: "person.2")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label("\(authStore.unreadState.dynamicUnread)", systemImage: "dot.radiowaves.left.and.right")
                            Label("\(authStore.unreadState.privateUnread)", systemImage: "bubble.left.and.bubble.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await authStore.sync()
                            }
                        } label: {
                            Label("同步个人中心", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        NavigationLink {
                            AccountManagementView()
                        } label: {
                            Label("管理账号", systemImage: "person.2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("账号已登录，正在同步个人中心信息。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await authStore.sync()
                            }
                        } label: {
                            Label("重新同步", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Text("首页推荐、视频详情、播放和搜索功能都可以直接匿名使用。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("登录后才会启用动态、私信、消息中心、弹幕发送和个人中心同步。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showLoginSheet = true
                    } label: {
                        Label("扫码登录", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink {
                        AccountManagementView()
                    } label: {
                        Label("账号管理", systemImage: "person.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct WatchHistoryRow: View {
    let record: WatchRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: record.video.coverURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle().fill(.quaternary)
                case .empty:
                    Rectangle().fill(.quaternary).overlay(ProgressView())
                @unknown default:
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 120, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(record.video.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(record.pageLabel)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accent)

                ProgressView(value: record.progressRatio)

                Text(BiliFormat.progressText(record.progressSeconds, total: record.pageDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let updated = BiliFormat.absoluteDate(record.updatedAt) {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FavoriteRow: View {
    let video: BiliVideo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: video.coverURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle().fill(.quaternary)
                case .empty:
                    Rectangle().fill(.quaternary).overlay(ProgressView())
                @unknown default:
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 120, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(video.owner.name, systemImage: "person.crop.circle")
                    Label(video.stats.plays, systemImage: "play.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text("时长 \(BiliFormat.durationText(video.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
