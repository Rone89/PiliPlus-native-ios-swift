import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published private(set) var profile: BiliUserProfile?
    @Published private(set) var videos: [BiliVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private let mid: Int
    private var page = 1
    private var hasMore = true

    init(mid: Int) {
        self.mid = mid
    }

    func loadIfNeeded() async {
        guard profile == nil else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        page = 1
        hasMore = true
        defer { isLoading = false }

        do {
            async let profileTask = BiliAPIClient.shared.fetchUserProfile(mid: mid)
            async let videosTask = BiliAPIClient.shared.fetchUserVideos(mid: mid, page: page)
            profile = try await profileTask
            videos = try await videosTask
            page = 2
            hasMore = !videos.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(after video: BiliVideo) async {
        guard hasMore, !isLoading, !isLoadingMore, videos.last?.id == video.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let items = try await BiliAPIClient.shared.fetchUserVideos(mid: mid, page: page)
            videos.append(contentsOf: items)
            page += 1
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UserProfileView: View {
    @StateObject private var viewModel: UserProfileViewModel

    init(mid: Int) {
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(mid: mid))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.profile == nil {
                ProgressView("正在加载 UP 主主页")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.profile == nil {
                ContentUnavailableView("加载失败", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(errorMessage))
            } else if let profile = viewModel.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        UserProfileHeader(profile: profile)

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("投稿视频")
                                    .font(.headline)
                                Spacer()
                                if let archiveCount = profile.archiveCountText {
                                    Text("\(archiveCount) 个")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if viewModel.videos.isEmpty {
                                Text("暂时没有公开视频")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.videos) { video in
                                    NavigationLink {
                                        VideoDetailView(bvid: video.bvid)
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
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle("UP 主主页")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

private struct UserProfileHeader: View {
    let profile: BiliUserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AsyncImage(url: profile.faceURL) { phase in
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
                .frame(width: 72, height: 72)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.name)
                        .font(.title2.bold())
                    Text("UID \(profile.mid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if !profile.sign.isEmpty {
                Text(profile.sign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                if let followersText = profile.followersText {
                    Label(followersText, systemImage: "person.2.fill")
                }
                if let followingText = profile.followingText {
                    Label(followingText, systemImage: "person.crop.circle.badge.plus")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
