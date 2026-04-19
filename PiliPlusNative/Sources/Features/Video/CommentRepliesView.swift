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
                            CommentRow(comment: rootComment)
                        }

                        Section("回复") {
                            if viewModel.replies.isEmpty {
                                Text("暂无回复")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.replies) { reply in
                                    CommentRow(comment: reply)
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
