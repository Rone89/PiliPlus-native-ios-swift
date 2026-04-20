import SwiftUI

@MainActor
final class DynamicFeedViewModel: ObservableObject {
    @Published private(set) var posts: [BiliDynamicPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private var nextOffset: String?
    private var hasMore = true

    func loadIfNeeded(session: BiliSession?) async {
        guard posts.isEmpty else { return }
        await refresh(session: session)
    }

    func refresh(session: BiliSession?) async {
        guard let session else {
            posts = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await BiliAPIClient.shared.fetchDynamicFeed(session: session)
            posts = await enrichPosts(result.0)
            nextOffset = result.1
            hasMore = result.2
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(session: BiliSession?, after post: BiliDynamicPost) async {
        guard let session, hasMore, !isLoading, !isLoadingMore, posts.last?.id == post.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await BiliAPIClient.shared.fetchDynamicFeed(session: session, offset: nextOffset)
            posts.append(contentsOf: await enrichPosts(result.0))
            nextOffset = result.1
            hasMore = result.2
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enrichPosts(_ items: [BiliDynamicPost]) async -> [BiliDynamicPost] {
        var enriched: [BiliDynamicPost] = []
        enriched.reserveCapacity(items.count)

        for post in items {
            if post.imageURLs.isEmpty,
               post.kindLabel.contains("图"),
               let images = try? await BiliAPIClient.shared.fetchDynamicImages(id: post.id),
               !images.isEmpty {
                enriched.append(post.withImageURLs(images))
            } else {
                enriched.append(post)
            }
        }

        return enriched
    }
}

struct DynamicFeedView: View {
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = DynamicFeedViewModel()
    @State private var showLoginSheet = false
    @State private var showComposeSheet = false

    var body: some View {
        Group {
            if let session = authStore.session, session.isLoggedIn {
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    ProgressView("正在加载动态")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                    ContentUnavailableView("动态加载失败", systemImage: "dot.radiowaves.left.and.right", description: Text(errorMessage))
                } else if viewModel.posts.isEmpty {
                    ContentUnavailableView("暂无动态", systemImage: "sparkles")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.posts) { post in
                                DynamicCard(post: post)
                                    .task {
                                        await viewModel.loadMoreIfNeeded(session: authStore.session, after: post)
                                    }
                            }

                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding()
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .refreshable {
                        await viewModel.refresh(session: authStore.session)
                        await authStore.sync()
                    }
                }
            } else {
                RequireLoginView(
                    title: "登录后查看动态",
                    message: "首页推荐、视频详情、播放和搜索都可以直接使用；扫码登录后才会同步关注动态和动态未读数。"
                ) {
                    showLoginSheet = true
                }
            }
        }
        .navigationTitle("动态")
        .toolbar {
            if authStore.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComposeSheet = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .task {
            await authStore.syncIfNeeded()
            await viewModel.loadIfNeeded(session: authStore.session)
        }
        .onChange(of: authStore.session) { _, session in
            Task {
                await viewModel.refresh(session: session)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .environmentObject(authStore)
        }
        .sheet(isPresented: $showComposeSheet) {
            ComposeDynamicView {
                Task {
                    await viewModel.refresh(session: authStore.session)
                }
            }
            .environmentObject(authStore)
        }
    }
}

struct DynamicCard: View {
    let post: BiliDynamicPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AsyncImage(url: post.authorAvatarURL) { phase in
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
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    if let mid = post.authorMid {
                        NavigationLink {
                            UserProfileView(mid: mid)
                        } label: {
                            Text(post.authorName)
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(post.authorName)
                            .font(.headline)
                    }

                    HStack(spacing: 8) {
                        Text(post.kindLabel)
                        if let relative = BiliFormat.relativeDate(post.publishedAt) {
                            Text(relative)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.title3.weight(.semibold))
            }

            if !post.text.isEmpty {
                Text(post.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !post.imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(post.imageURLs, id: \.self) { imageURL in
                            AsyncImage(url: imageURL) { phase in
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
                            .frame(width: 220, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let coverURL = post.coverURL {
                AsyncImage(url: coverURL) { phase in
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
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .center)
            }

            if let bvid = post.videoBVID {
                NavigationLink {
                    VideoDetailView(bvid: bvid, aid: nil)
                } label: {
                    Label("打开视频详情", systemImage: "play.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                DynamicDetailView(dynamicID: post.id)
            } label: {
                Label("查看动态详情", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct RequireLoginView: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text(message)
        )
        .overlay(alignment: .bottom) {
            Button(action: action) {
                Label("扫码登录", systemImage: "qrcode")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }
}
