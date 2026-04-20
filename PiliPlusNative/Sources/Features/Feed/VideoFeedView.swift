import SwiftUI

@MainActor
final class VideoFeedViewModel: ObservableObject {
    @Published private(set) var videos: [BiliVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private var recommendationCursor = 0
    private var hasMore = true

    func loadIfNeeded(session: BiliSession?, preferPersonalized: Bool) async {
        guard videos.isEmpty else { return }
        await refresh(session: session, preferPersonalized: preferPersonalized)
    }

    func refresh(session: BiliSession?, preferPersonalized: Bool) async {
        if !videos.isEmpty {
            recommendationCursor += 1
        }
        hasMore = true
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await fetchBatch(reset: true, session: session, preferPersonalized: preferPersonalized)
            videos = items
            hasMore = !items.isEmpty
            if items.isEmpty {
                errorMessage = "当前推荐流暂时为空，请稍后重试"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(after video: BiliVideo, session: BiliSession?, preferPersonalized: Bool) async {
        guard hasMore, !isLoading, !isLoadingMore, videos.last?.id == video.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let items = try await fetchBatch(reset: false, session: session, preferPersonalized: preferPersonalized)
            videos.append(contentsOf: items)
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchBatch(reset: Bool, session: BiliSession?, preferPersonalized: Bool) async throws -> [BiliVideo] {
        let currentCursor = reset ? recommendationCursor : recommendationCursor + 1
        let items = try await BiliAPIClient.shared.fetchRecommended(
            freshIndex: currentCursor,
            session: session,
            preferPersonalized: preferPersonalized
        )
        recommendationCursor = currentCursor
        return items
    }
}

struct VideoFeedView: View {
    @EnvironmentObject private var authStore: AuthStore
    @AppStorage("preference_recommend_with_account") private var recommendWithAccount = true

    private let externalRefreshToken: Int
    @StateObject private var viewModel = VideoFeedViewModel()

    init(externalRefreshToken: Int = 0) {
        self.externalRefreshToken = externalRefreshToken
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.videos.isEmpty {
                ProgressView("正在加载首页推荐")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.videos.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("首页推荐")
                                .font(.largeTitle.bold())
                            Text(recommendModeSubtitle)
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
                                    await viewModel.loadMoreIfNeeded(
                                        after: video,
                                        session: authStore.session,
                                        preferPersonalized: preferPersonalized
                                    )
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
                    await viewModel.refresh(session: authStore.session, preferPersonalized: preferPersonalized)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            await viewModel.loadIfNeeded(session: authStore.session, preferPersonalized: preferPersonalized)
        }
        .task(id: externalRefreshToken) {
            guard externalRefreshToken != 0 else { return }
            await viewModel.refresh(session: authStore.session, preferPersonalized: preferPersonalized)
        }
        .task(id: recommendWithAccount) {
            guard !viewModel.videos.isEmpty else { return }
            await viewModel.refresh(session: authStore.session, preferPersonalized: preferPersonalized)
        }
    }

    private var preferPersonalized: Bool {
        recommendWithAccount && authStore.isLoggedIn
    }

    private var recommendModeSubtitle: String {
        preferPersonalized ? "当前使用登录账号参与推荐" : "当前使用匿名推荐"
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
