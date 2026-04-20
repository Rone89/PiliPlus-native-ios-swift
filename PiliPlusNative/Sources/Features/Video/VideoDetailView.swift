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

    private let bvid: String?
    private let aid: Int?
    private var commentsNextOffset = ""
    private var commentsReachedEnd = false

    init(bvid: String?, aid: Int?) {
        self.bvid = bvid
        self.aid = aid
    }

    var canLoadMoreComments: Bool {
        !commentsReachedEnd && !comments.isEmpty
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
            let detail: BiliVideoDetail
            if let bvid {
                detail = try await BiliAPIClient.shared.fetchVideoDetail(bvid: bvid)
            } else if let aid {
                detail = try await BiliAPIClient.shared.fetchVideoDetail(aid: aid)
            } else {
                throw APIError.invalidResponse("缺少视频标识")
            }

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: VideoDetailViewModel
    @State private var selectedPageIndex = 0
    @State private var selectedComment: BiliComment?

    init(bvid: String?, aid: Int?) {
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(bvid: bvid, aid: aid))
    }

    init(bvid: String) {
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(bvid: bvid, aid: nil))
    }

    init(aid: Int) {
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(bvid: nil, aid: aid))
    }

    var body: some View {
        content
            .navigationTitle("视频详情")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.detail == nil {
            ProgressView("正在加载视频详情")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, viewModel.detail == nil {
            ContentUnavailableView("视频加载失败", systemImage: "play.slash", description: Text(errorMessage))
        } else if let detail = viewModel.detail {
            loadedContent(detail: detail)
        } else {
            ContentUnavailableView("暂无视频内容", systemImage: "play.slash")
        }
    }

    private func loadedContent(detail: BiliVideoDetail) -> some View {
        let resumeRecord = libraryStore.historyRecord(video: detail.video)
        let resumeIndex = resumeRecord.flatMap { record in
            detail.pages.firstIndex(where: { $0.cid == record.pageCID })
        } ?? 0

        return GeometryReader { proxy in
            let contentWidth = min(max(proxy.size.width - 32, 0), 420)
            let isWide = horizontalSizeClass == .regular && proxy.size.width >= 1000 && proxy.size.height >= 700

            ScrollView {
                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: 20) {
                            leftColumn(detail: detail, resumeRecord: resumeRecord, resumeIndex: resumeIndex)
                                .frame(maxWidth: min(max(proxy.size.width * 0.42, 360), 520), alignment: .topLeading)
                            rightColumn(detail: detail)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            leftColumn(detail: detail, resumeRecord: resumeRecord, resumeIndex: resumeIndex)
                            rightColumn(detail: detail)
                        }
                        .frame(maxWidth: contentWidth, alignment: .topLeading)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
            }
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
            if let record = libraryStore.historyRecord(video: detail.video),
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

    @ViewBuilder
    private func leftColumn(detail: BiliVideoDetail, resumeRecord: WatchRecord?, resumeIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            coverSection(detail: detail)
            metadataSection(detail: detail)
            actionSection(detail: detail)

            if let resumeRecord {
                resumeSection(detail: detail, record: resumeRecord, resumeIndex: resumeIndex)
            }

            if !detail.pages.isEmpty {
                playbackSection(detail: detail)
            }
        }
    }

    @ViewBuilder
    private func rightColumn(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            commentsSection

            if !detail.related.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("相关推荐")
                        .font(.headline)

                    ForEach(detail.related) { video in
                        HStack {
                            Spacer(minLength: 0)
                            NavigationLink {
                                VideoDetailView(bvid: video.bvid, aid: video.aid)
                            } label: {
                                VideoCardView(video: video)
                                    .frame(maxWidth: 420)
                            }
                            .buttonStyle(.plain)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func coverSection(detail: BiliVideoDetail) -> some View {
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
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func metadataSection(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.video.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ownerView(detail: detail)
                    statsView(detail: detail)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ownerView(detail: detail)
                    statsView(detail: detail)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let relativeDate = BiliFormat.relativeDate(detail.video.publishedAt) {
                Text(relativeDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    identifierView(detail: detail)
                }
                VStack(alignment: .leading, spacing: 4) {
                    identifierView(detail: detail)
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if !detail.video.descriptionText.isEmpty {
                Text(detail.video.descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func ownerView(detail: BiliVideoDetail) -> some View {
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
    }

    @ViewBuilder
    private func statsView(detail: BiliVideoDetail) -> some View {
        Group {
            Label(detail.video.stats.plays, systemImage: "play.fill")
            if let likes = detail.video.stats.likes {
                Label(likes, systemImage: "hand.thumbsup.fill")
            }
        }
    }

    @ViewBuilder
    private func identifierView(detail: BiliVideoDetail) -> some View {
        if let bvid = detail.video.bvid {
            Text(bvid)
        }
        if let aid = detail.video.aid {
            Text("av\(aid)")
        }
    }

    @ViewBuilder
    private func actionSection(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷操作")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
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
