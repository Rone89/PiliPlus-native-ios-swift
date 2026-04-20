import SwiftUI

@MainActor
final class VideoFeedViewModel: ObservableObject {
    @Published private(set) var videos: [BiliVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    let kind: FeedKind

    private var page = 1
    private var hasMore = true

    init(kind: FeedKind) {
        self.kind = kind
    }

    func loadIfNeeded() async {
        guard videos.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        page = 1
        hasMore = true
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await fetch(page: page)
            videos = items
            page += 1
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(after video: BiliVideo) async {
        guard hasMore, !isLoading, !isLoadingMore, videos.last?.id == video.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let items = try await fetch(page: page)
            videos.append(contentsOf: items)
            page += 1
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetch(page: Int) async throws -> [BiliVideo] {
        switch kind {
        case .recommend:
            return try await BiliAPIClient.shared.fetchRecommended(page: page)
        case .popular:
            return try await BiliAPIClient.shared.fetchPopular(page: page)
        }
    }
}

struct VideoFeedView: View {
    private let kind: FeedKind
    private let externalRefreshToken: Int
    @StateObject private var viewModel: VideoFeedViewModel

    init(kind: FeedKind, externalRefreshToken: Int = 0) {
        self.kind = kind
        self.externalRefreshToken = externalRefreshToken
        _viewModel = StateObject(wrappedValue: VideoFeedViewModel(kind: kind))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                ProgressView("正在加载\(kind.title)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.videos.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.title)
                                .font(.largeTitle.bold())
                            Text(kind.subtitle)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        LazyVStack(spacing: 14) {
                            ForEach(viewModel.videos) { video in
                                NavigationLink {
                                    VideoDetailView(bvid: video.bvid, aid: video.aid)
                                } label: {
                                    VideoCardView(video: video)
                                }
                                .buttonStyle(.plain)
                                .task {
                                    await viewModel.loadMoreIfNeeded(after: video)
                                }
                            }

                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(kind.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: externalRefreshToken) {
            guard externalRefreshToken != 0 else { return }
            await viewModel.refresh()
        }
    }
}

struct VideoCardView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    let video: BiliVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.coverURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay(Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary))
                    case .empty:
                        Rectangle()
                            .fill(.quaternary)
                            .overlay(ProgressView())
                    @unknown default:
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(height: 208)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if libraryStore.isFavorite(video) {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(8)
                        .background(.thinMaterial, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(12)
                }

                Text(BiliFormat.durationText(video.duration))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.7), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    Label(video.owner.name, systemImage: "person.crop.circle")
                    Label(video.stats.plays, systemImage: "play.fill")
                    if let danmaku = video.stats.danmaku {
                        Label(danmaku, systemImage: "text.bubble")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if !video.descriptionText.isEmpty {
                    Text(video.descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
