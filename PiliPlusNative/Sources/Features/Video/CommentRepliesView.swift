import SwiftUI

@MainActor
final class CommentRepliesViewModel: ObservableObject {
    @Published private(set) var replies: [BiliComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private let aid: Int
    private let rootCommentID: Int
    private var page = 1
    private var hasMore = true

    init(aid: Int, rootCommentID: Int) {
        self.aid = aid
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
            let items = try await BiliAPIClient.shared.fetchCommentReplies(aid: aid, rootCommentID: rootCommentID, page: page)
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
            let items = try await BiliAPIClient.shared.fetchCommentReplies(aid: aid, rootCommentID: rootCommentID, page: page)
            replies.append(contentsOf: items)
            page += 1
            hasMore = items.count >= 20
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CommentRepliesView: View {
    let rootComment: BiliComment

    @StateObject private var viewModel: CommentRepliesViewModel

    init(aid: Int, rootComment: BiliComment) {
        self.rootComment = rootComment
        _viewModel = StateObject(wrappedValue: CommentRepliesViewModel(aid: aid, rootCommentID: rootComment.id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.replies.isEmpty {
                    ProgressView("正在加载回复")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.replies.isEmpty {
                    ContentUnavailableView("加载失败", systemImage: "text.bubble", description: Text(errorMessage))
                } else {
                    List {
                        Section("原评论") {
                            ReplyCommentRow(comment: rootComment)
                        }

                        Section("回复") {
                            if viewModel.replies.isEmpty {
                                Text("暂无回复")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.replies) { reply in
                                    ReplyCommentRow(comment: reply)
                                        .task {
                                            await viewModel.loadMoreIfNeeded(after: reply)
                                        }
                                }

                                if viewModel.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await viewModel.refresh()
                    }
                }
            }
            .navigationTitle("评论回复")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }
}

private struct ReplyCommentRow: View {
    let comment: BiliComment

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
                        Label("\(comment.replyCount)", systemImage: "text.bubble")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
