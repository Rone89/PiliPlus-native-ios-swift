import AVKit
import SwiftUI

private struct VideoDetailSectionHeightKey: PreferenceKey {
    static var defaultValue: [VideoDetailSection: CGFloat] = [:]

    static func reduce(value: inout [VideoDetailSection: CGFloat], nextValue: () -> [VideoDetailSection: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum VideoDetailSection: String, CaseIterable, Identifiable {
    case info
    case comments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info:
            return "视频资料"
        case .comments:
            return "视频评论"
        }
    }
}

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

@MainActor
final class InlinePlayerViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var currentSeconds = 0.0
    @Published private(set) var playback: BiliPlayback?
    @Published var errorMessage: String?
    @Published var selectedPageIndex: Int
    @Published var playbackRate = AppPreferences.playbackRate

    let detail: BiliVideoDetail
    let player = AVPlayer()

    private weak var libraryStore: LibraryStore?
    private var timeObserver: Any?
    private var initialPageIndex: Int

    init(detail: BiliVideoDetail, initialPageIndex: Int) {
        self.detail = detail
        self.initialPageIndex = min(max(initialPageIndex, 0), max(detail.pages.count - 1, 0))
        self.selectedPageIndex = min(max(initialPageIndex, 0), max(detail.pages.count - 1, 0))
    }

    var currentPage: BiliVideoPage? {
        detail.pages[safe: selectedPageIndex]
    }

    var canGoToPreviousPage: Bool { selectedPageIndex > 0 }
    var canGoToNextPage: Bool { selectedPageIndex < detail.pages.count - 1 }

    func attachLibrary(_ store: LibraryStore) {
        libraryStore = store
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }
                self.currentSeconds = seconds
            }
        }
    }

    func loadIfNeeded() async {
        guard playback == nil else { return }
        await loadCurrentPage()
    }

    func loadCurrentPage() async {
        guard let page = currentPage else { return }
        guard let videoIdentifier = detail.video.bvid ?? detail.video.aid.map({ "av\($0)" }) else {
            errorMessage = "缺少视频标识"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await BiliAPIClient.shared.fetchPlayback(bvid: videoIdentifier, cid: page.cid)
            self.playback = playback
            configurePlayer(with: playback.streamURL)
            libraryStore?.updateWatchRecord(video: detail.video, page: page, progressSeconds: currentSeconds)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPage(at index: Int) async {
        guard selectedPageIndex != index else { return }
        selectedPageIndex = index
        await loadCurrentPage()
    }

    func goToPreviousPage() async {
        guard canGoToPreviousPage else { return }
        await selectPage(at: selectedPageIndex - 1)
    }

    func goToNextPage() async {
        guard canGoToNextPage else { return }
        await selectPage(at: selectedPageIndex + 1)
    }

    func play() {
        player.playImmediately(atRate: Float(playbackRate))
    }

    func pause() {
        player.pause()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        AppPreferences.playbackRate = rate
        if player.timeControlStatus != .paused {
            play()
        }
    }

    func tearDown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    private func configurePlayer(with url: URL) {
        let refererTarget = detail.video.pageURL?.absoluteString ?? "https://www.bilibili.com"
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Referer": refererTarget,
                "Origin": "https://www.bilibili.com",
                "User-Agent": BiliAPIClient.webUserAgent
            ]
        ]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        currentSeconds = 0
        play()
    }
}

struct VideoDetailView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: VideoDetailViewModel
    @State private var playerModel: InlinePlayerViewModel?
    @State private var selectedPageIndex = 0
    @State private var selectedComment: BiliComment?
    @State private var selectedSection: VideoDetailSection = .info
    @State private var sectionHeights: [VideoDetailSection: CGFloat] = [:]

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

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let playerModel {
                    inlinePlayerSection(model: playerModel)
                } else {
                    ProgressView("正在准备播放器")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                Picker("详情分区", selection: $selectedSection) {
                    ForEach(VideoDetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    if selectedSection == .info {
                        infoSection(detail: detail, resumeRecord: resumeRecord, resumeIndex: resumeIndex)
                            .background(sectionHeightReader(for: .info))
                    } else {
                        commentsSection
                            .background(sectionHeightReader(for: .comments))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(minHeight: max(sectionHeights.values.max() ?? 0, 320), alignment: .topLeading)
                .animation(.easeInOut(duration: 0.22), value: selectedSection)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
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
            } else {
                selectedPageIndex = resumeIndex
            }

            let model = InlinePlayerViewModel(detail: detail, initialPageIndex: selectedPageIndex)
            model.attachLibrary(libraryStore)
            playerModel = model
            await model.loadIfNeeded()
        }
        .onDisappear {
            playerModel?.tearDown()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                playerModel?.pause()
            }
        }
        .sheet(item: $selectedComment) { comment in
            if let aid = detail.video.aid {
                CommentRepliesView(aid: aid, rootComment: comment)
            }
        }
        .onPreferenceChange(VideoDetailSectionHeightKey.self) { heights in
            sectionHeights.merge(heights, uniquingKeysWith: { _, new in new })
        }
    }

    private func inlinePlayerSection(model: InlinePlayerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VideoPlayer(player: model.player)
                .frame(height: 236)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if model.isLoading {
                ProgressView("正在获取播放地址")
            } else if let errorMessage = model.errorMessage {
                ContentUnavailableView("播放失败", systemImage: "play.slash.fill", description: Text(errorMessage))
            }

            if let page = model.currentPage {
                Text(page.label)
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await model.goToPreviousPage() }
                } label: {
                    Label("上一 P", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canGoToPreviousPage)

                Button {
                    model.play()
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.pause()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.goToNextPage() }
                } label: {
                    Label("下一 P", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canGoToNextPage)
            }

            if !model.detail.pages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(model.detail.pages.enumerated()), id: \.offset) { index, page in
                            Button {
                                Task { await model.selectPage(at: index) }
                            } label: {
                                Text(page.label)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(index == model.selectedPageIndex ? AppTheme.accent : AppTheme.card, in: Capsule())
                                    .foregroundStyle(index == model.selectedPageIndex ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Picker("默认倍速", selection: playerRateBinding(model)) {
                Text("0.75x").tag(0.75)
                Text("1.0x").tag(1.0)
                Text("1.25x").tag(1.25)
                Text("1.5x").tag(1.5)
                Text("2.0x").tag(2.0)
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func playerRateBinding(_ model: InlinePlayerViewModel) -> Binding<Double> {
        Binding(
            get: { model.playbackRate },
            set: { model.setPlaybackRate($0) }
        )
    }

    private func sectionHeightReader(for section: VideoDetailSection) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: VideoDetailSectionHeightKey.self, value: [section: proxy.size.height])
        }
    }

    private func infoSection(detail: BiliVideoDetail, resumeRecord: WatchRecord?, resumeIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            metadataSection(detail: detail)
            actionSection(detail: detail)

            if let resumeRecord {
                resumeSection(detail: detail, record: resumeRecord, resumeIndex: resumeIndex)
            }

            relatedSection(detail: detail)
        }
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

            HStack(spacing: 10) {
                if let bvid = detail.video.bvid {
                    Text(bvid)
                }
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

    private func relatedSection(detail: BiliVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("更多视频推荐")
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
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
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
