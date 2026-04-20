import SwiftUI

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published private(set) var detail: BiliVideoDetail?
    @Published private(set) var comments: [BiliComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingComments = false
    @Published private(set) var isLoadingMoreComments = false
    @Published var errorMessage: String?
    @Published var commentsError: String?

    private let bvid: String
    private var commentsNextOffset = ""
    private var commentsReachedEnd = false

    var canLoadMoreComments: Bool {
        !commentsReachedEnd && !comments.isEmpty
    }

    init(bvid: String) {
        self.bvid = bvid
    }

    func loadIfNeeded() async {
        guard detail == nil else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        comments = []
        commentsError = nil
        commentsNextOffset = ""
        commentsReachedEnd = false
        defer { isLoading = false }

        do {
            let detail = try await BiliAPIClient.shared.fetchVideoDetail(bvid: bvid)
            self.detail = detail
            if let aid = detail.video.aid {
                await loadComments(aid: aid, reset: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreComments() async {
        guard let aid = detail?.video.aid, !commentsReachedEnd, !isLoadingComments, !isLoadingMoreComments else { return }
        await loadComments(aid: aid, reset: false)
    }

    private func loadComments(aid: Int, reset: Bool) async {
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
            let page = try await BiliAPIClient.shared.fetchComments(oid: aid, type: 1, nextOffset: reset ? "" : commentsNextOffset)
            if reset {
                comments = page.comments
            } else {
                comments.append(contentsOf: page.comments)
            }
            commentsNextOffset = page.nextOffset ?? ""
            commentsReachedEnd = page.isEnd || page.nextOffset == nil
        } catch {
            commentsError = error.localizedDescription
        }
    }
}

struct VideoDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @StateObject private var viewModel: VideoDetailViewModel
    @State private var selectedPageIndex = 0
    @State private var selectedComment: BiliComment?

    init(bvid: String) {
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(bvid: bvid))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView("正在加载视频详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.detail == nil {
                ContentUnavailableView("视频加载失败", systemImage: "play.slash", description: Text(errorMessage))
            } else if let detail = viewModel.detail {
                let resumeRecord = libraryStore.historyRecord(for: detail.video.bvid)
                let resumeIndex = resumeRecord.flatMap { record in
                    detail.pages.firstIndex(where: { $0.cid == record.pageCID })
                } ?? 0

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        AsyncImage(url: detail.video.coverURL) { phase in
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
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                        VStack(alignment: .leading, spacing: 12) {
                            Text(detail.video.title)
                                .font(.title2.bold())

                            HStack(spacing: 12) {
                                if let mid = detail.video.owner.mid {
                                    NavigationLink {
                                        UserProfileView(mid: mid)
                                    } label: {
                                        Label(detail.video.owner.name, systemImage: "person.crop.circle")
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Label(detail.video.owner.name, systemImage: "person.crop.circle")
                                }
                                Label(detail.video.stats.plays, systemImage: "play.fill")
                                if let likes = detail.video.stats.likes {
                                    Label(likes, systemImage: "hand.thumbsup.fill")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            if let relativeDate = BiliFormat.relativeDate(detail.video.publishedAt) {
                                Text(relativeDate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Text(detail.video.bvid)
                                if let aid = detail.video.aid {
                                    Text("av\(aid)")
                                }
                            }
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                            if !detail.video.descriptionText.isEmpty {
                                Text(detail.video.descriptionText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        actionSection(detail: detail)

                        if let resumeRecord {
                            resumeSection(detail: detail, record: resumeRecord, resumeIndex: resumeIndex)
                        }

                        if !detail.pages.isEmpty {
                            playbackSection(detail: detail)
                        }

                        commentsSection

                        if !detail.related.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("相关推荐")
                                    .font(.headline)

                                ForEach(detail.related) { video in
                                    NavigationLink {
                                        VideoDetailView(bvid: video.bvid)
                                    } label: {
                                        VideoCardView(video: video)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            libraryStore.toggleFavorite(detail.video)
                        } label: {
                            Image(systemName: libraryStore.isFavorite(detail.video) ? "star.fill" : "star")
                                .foregroundStyle(libraryStore.isFavorite(detail.video) ? .yellow : .primary)
                        }

                        if let pageURL = detail.video.pageURL {
                            ShareLink(item: pageURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .task(id: detail.video.id) {
                    libraryStore.refreshSnapshots(with: detail.video)
                    if let record = libraryStore.historyRecord(for: detail.video.bvid),
                       let index = detail.pages.firstIndex(where: { $0.cid == record.pageCID }) {
                        selectedPageIndex = index
                    }
                }
                .sheet(item: $selectedComment) { comment in
                    if let aid = detail.video.aid {
                        CommentRepliesView(aid: aid, rootComment: comment)
                    }
                }
            }
        }
        .navigationTitle("视频详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func actionSection(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷操作")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    libraryStore.toggleFavorite(detail.video)
                } label: {
                    actionButtonLabel(
                        title: libraryStore.isFavorite(detail.video) ? "已收藏" : "收藏",
                        systemImage: libraryStore.isFavorite(detail.video) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.plain)

                if let pageURL = detail.video.pageURL {
                    Link(destination: pageURL) {
                        actionButtonLabel(title: "Safari", systemImage: "safari")
                    }
                    .buttonStyle(.plain)
                }

                if let mid = detail.video.owner.mid {
                    NavigationLink {
                        UserProfileView(mid: mid)
                    } label: {
                        actionButtonLabel(title: "UP 主页", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func resumeSection(detail: BiliVideoDetail, record: WatchRecord, resumeIndex: Int) -> some View {
        NavigationLink {
            PlayerView(detail: detail, initialPageIndex: resumeIndex, startAtSeconds: record.progressSeconds)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("继续播放", systemImage: "play.circle.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }

                Text(record.pageLabel)
                    .font(.subheadline.weight(.medium))
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func playbackSection(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放")
                .font(.headline)

            Picker("当前分 P", selection: $selectedPageIndex) {
                ForEach(Array(detail.pages.enumerated()), id: \.offset) { index, page in
                    Text(page.label).tag(index)
                }
            }
            .pickerStyle(.menu)

            NavigationLink {
                PlayerView(detail: detail, initialPageIndex: selectedPageIndex)
            } label: {
                Label("播放当前分 P", systemImage: "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var commentsSection: some View {
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
                    CommentRow(comment: comment) {
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

    private func actionButtonLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CommentRow: View {
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
