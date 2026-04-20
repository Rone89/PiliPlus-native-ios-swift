import SwiftUI

@MainActor
final class DynamicDetailViewModel: ObservableObject {
    @Published private(set) var post: BiliDynamicPost?
    @Published private(set) var comments: [BiliComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingComments = false
    @Published private(set) var isLoadingMoreComments = false
    @Published var errorMessage: String?
    @Published var commentsError: String?

    private let dynamicID: String
    private var nextOffset = ""
    private var commentsReachedEnd = false

    init(dynamicID: String) {
        self.dynamicID = dynamicID
    }

    var canLoadMoreComments: Bool {
        !commentsReachedEnd && !comments.isEmpty
    }

    func loadIfNeeded(session: BiliSession?) async {
        guard post == nil else { return }
        await reload(session: session)
    }

    func reload(session: BiliSession?) async {
        isLoading = true
        errorMessage = nil
        comments = []
        commentsError = nil
        nextOffset = ""
        commentsReachedEnd = false
        defer { isLoading = false }

        do {
            let post = try await BiliAPIClient.shared.fetchDynamicDetail(id: dynamicID, session: session)
            self.post = post
            await loadComments(reset: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreComments() async {
        guard !commentsReachedEnd, !isLoadingComments, !isLoadingMoreComments else { return }
        await loadComments(reset: false)
    }

    func toggleLike(session: BiliSession?) async {
        guard let session, let post else { return }
        do {
            try await BiliAPIClient.shared.toggleDynamicLike(session: session, dynamicID: post.id, currentlyLiked: post.isLiked)
            await reload(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadComments(reset: Bool) async {
        guard let post else { return }
        let oid = post.commentID ?? Int(post.id)
        let type = post.commentType ?? 17
        guard let oid else { return }
        if reset {
            isLoadingComments = true
            commentsError = nil
        } else {
            isLoadingMoreComments = true
        }

        defer {
            if reset {
                isLoadingComments = false
            } else {
                isLoadingMoreComments = false
            }
        }

        do {
            let page = try await BiliAPIClient.shared.fetchComments(oid: oid, type: type, nextOffset: reset ? "" : nextOffset)
            if reset {
                comments = page.comments
            } else {
                comments.append(contentsOf: page.comments)
            }
            nextOffset = page.nextOffset ?? ""
            commentsReachedEnd = page.isEnd || page.nextOffset == nil
        } catch {
            commentsError = error.localizedDescription
        }
    }
}

struct DynamicDetailView: View {
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel: DynamicDetailViewModel
    @State private var selectedComment: BiliComment?

    init(dynamicID: String) {
        _viewModel = StateObject(wrappedValue: DynamicDetailViewModel(dynamicID: dynamicID))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.post == nil {
                ProgressView("正在加载动态详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.post == nil {
                ContentUnavailableView("动态加载失败", systemImage: "dot.radiowaves.left.and.right", description: Text(errorMessage))
            } else if let post = viewModel.post {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DynamicCard(post: post)

                        actionSection(post: post)
                        commentsSection(post: post)
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .sheet(item: $selectedComment) { comment in
                    if let oid = post.commentID, let type = post.commentType {
                        DynamicCommentRepliesView(oid: oid, type: type, rootComment: comment)
                    }
                }
            } else {
                ContentUnavailableView("暂无动态内容", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .navigationTitle("动态详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded(session: authStore.session)
        }
    }

    @ViewBuilder
    private func actionSection(post: BiliDynamicPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("互动")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.toggleLike(session: authStore.session)
                    }
                } label: {
                    Label(post.likeCount ?? "赞", systemImage: post.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(post.isLiked ? AppTheme.accent : .accentColor)

                Label(post.commentCount ?? "评论", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Label(post.forwardCount ?? "转发", systemImage: "arrow.2.squarepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func commentsSection(post: BiliDynamicPost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("评论")
                    .font(.headline)
                if viewModel.isLoadingComments {
                    ProgressView()
                }
            }

            if let commentsError = viewModel.commentsError, viewModel.comments.isEmpty {
                Text(commentsError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if viewModel.comments.isEmpty && !viewModel.isLoadingComments {
                Text("暂无可展示评论")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.comments) { comment in
                    DynamicCommentRow(comment: comment) {
                        if comment.replyCount > 0 {
                            selectedComment = comment
                        }
                    }
                }

                if viewModel.isLoadingMoreComments {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.canLoadMoreComments {
                    Button("加载更多评论") {
                        Task {
                            await viewModel.loadMoreComments()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct DynamicCommentRow: View {
    let comment: BiliComment
    var onTapReply: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: comment.avatarURL) { phase in
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
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let memberMid = comment.memberMid {
                        NavigationLink {
                            UserProfileView(mid: memberMid)
                        } label: {
                            Text(comment.authorName)
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(comment.authorName)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if let relative = BiliFormat.relativeDate(comment.publishedAt) {
                        Text(relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(comment.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    if let likeCount = comment.likeCount {
                        Label(likeCount, systemImage: "hand.thumbsup")
                    }
                    if comment.replyCount > 0 {
                        if let onTapReply {
                            Button {
                                onTapReply()
                            } label: {
                                Label("\(comment.replyCount)", systemImage: "text.bubble")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Label("\(comment.replyCount)", systemImage: "text.bubble")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DynamicCommentRepliesView: View {
    let oid: Int
    let type: Int
    let rootComment: BiliComment

    @StateObject private var viewModel: DynamicCommentRepliesViewModel

    init(oid: Int, type: Int, rootComment: BiliComment) {
        self.oid = oid
        self.type = type
        self.rootComment = rootComment
        _viewModel = StateObject(wrappedValue: DynamicCommentRepliesViewModel(oid: oid, type: type, rootCommentID: rootComment.id))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("原评论") {
                    DynamicCommentRow(comment: rootComment)
                }

                Section("回复") {
                    if viewModel.isLoading && viewModel.replies.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let errorMessage = viewModel.errorMessage, viewModel.replies.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if viewModel.replies.isEmpty {
                        Text("暂无回复")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.replies) { reply in
                            DynamicCommentRow(comment: reply)
                                .task {
                                    await viewModel.loadMoreIfNeeded(after: reply)
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }
}

@MainActor
final class DynamicCommentRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [BiliComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private let oid: Int
    private let type: Int
    private let rootCommentID: Int
    private var page = 1
    private var hasMore = true

    init(oid: Int, type: Int, rootCommentID: Int) {
        self.oid = oid
        self.type = type
        self.rootCommentID = rootCommentID
    }

    func loadIfNeeded() async {
        guard replies.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        page = 1
        hasMore = true
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await BiliAPIClient.shared.fetchCommentReplies(oid: oid, rootCommentID: rootCommentID, type: type, page: page)
            replies = items
            page = 2
            hasMore = items.count >= 20
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(after reply: BiliComment) async {
        guard hasMore, !isLoading, !isLoadingMore, replies.last?.id == reply.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let items = try await BiliAPIClient.shared.fetchCommentReplies(oid: oid, rootCommentID: rootCommentID, type: type, page: page)
            replies.append(contentsOf: items)
            page += 1
            hasMore = items.count >= 20
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
