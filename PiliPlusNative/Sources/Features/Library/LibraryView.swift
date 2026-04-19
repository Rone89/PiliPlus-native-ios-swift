import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showClearHistoryConfirmation = false
    @State private var showClearFavoritesConfirmation = false

    var body: some View {
        Group {
            if libraryStore.history.isEmpty && libraryStore.favorites.isEmpty {
                ContentUnavailableView(
                    "还没有内容",
                    systemImage: "rectangle.stack.person.crop",
                    description: Text("开始播放视频后会记录观看历史，也可以在详情页把视频加入本地收藏。")
                )
            } else {
                List {
                    if !libraryStore.history.isEmpty {
                        Section("继续观看") {
                            ForEach(libraryStore.history) { record in
                                NavigationLink {
                                    VideoDetailView(bvid: record.video.bvid)
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
                                    VideoDetailView(bvid: video.bvid)
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
            }
        }
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
