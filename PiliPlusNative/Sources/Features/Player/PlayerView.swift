import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var playback: BiliPlayback?
    @Published private(set) var isLoading = false
    @Published private(set) var currentSeconds = 0.0
    @Published private(set) var danmakuItems: [BiliDanmakuItem] = []
    @Published private(set) var activeDanmaku: [ActiveDanmakuItem] = []
    @Published private(set) var isSendingDanmaku = false
    @Published var errorMessage: String?
    @Published var danmakuError: String?
    @Published var danmakuInput = ""
    @Published var selectedPageIndex: Int
    @Published var playbackRate = AppPreferences.playbackRate
    @Published var showDanmaku = AppPreferences.showDanmaku

    let detail: BiliVideoDetail
    let player = AVPlayer()

    private let initialPageIndex: Int
    private let initialStartAtSeconds: Double?
    private weak var libraryStore: LibraryStore?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var nextDanmakuIndex = 0
    private var nextDanmakuLane = 0
    private var lastObservedSeconds = 0.0
    private var lastPersistedSeconds = 0.0

    init(detail: BiliVideoDetail, initialPageIndex: Int, startAtSeconds: Double? = nil) {
        self.detail = detail
        self.initialPageIndex = min(max(initialPageIndex, 0), max(detail.pages.count - 1, 0))
        self.initialStartAtSeconds = startAtSeconds
        self.selectedPageIndex = min(max(initialPageIndex, 0), max(detail.pages.count - 1, 0))
    }

    var currentPage: BiliVideoPage? {
        detail.pages[safe: selectedPageIndex]
    }

    var canGoToPreviousPage: Bool {
        selectedPageIndex > 0
    }

    var canGoToNextPage: Bool {
        selectedPageIndex < detail.pages.count - 1
    }

    func attachLibrary(_ store: LibraryStore) {
        guard libraryStore !== store else { return }
        libraryStore = store
        if timeObserver == nil {
            configureTimeObserver()
        }
        if endObserver == nil {
            configureEndObserver()
        }
    }

    func loadCurrentPage() async {
        guard let page = currentPage else { return }
        guard let videoIdentifier = detail.video.bvid ?? detail.video.aid.map({ "av\($0)" }) else {
            errorMessage = "缺少视频标识"
            return
        }
        isLoading = true
        errorMessage = nil
        danmakuError = nil
        activeDanmaku = []
        danmakuItems = []
        nextDanmakuIndex = 0
        nextDanmakuLane = 0
        lastObservedSeconds = 0
        lastPersistedSeconds = 0
        defer { isLoading = false }

        do {
            async let playbackTask = BiliAPIClient.shared.fetchPlayback(bvid: videoIdentifier, cid: page.cid)
            async let danmakuTask = BiliAPIClient.shared.fetchDanmaku(cid: page.cid)

            let playback = try await playbackTask
            self.playback = playback
            let resumeProgress = resumeProgress(for: page)
            currentSeconds = resumeProgress ?? 0
            lastPersistedSeconds = resumeProgress ?? 0
            configurePlayer(with: playback.streamURL, startAtSeconds: resumeProgress)
            danmakuItems = (try? await danmakuTask) ?? []

            libraryStore?.updateWatchRecord(video: detail.video, page: page, progressSeconds: resumeProgress ?? 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPage(at index: Int) async {
        guard selectedPageIndex != index else { return }
        persistCurrentProgress()
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

    func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        AppPreferences.playbackRate = rate
        if player.timeControlStatus != .paused {
            player.playImmediately(atRate: Float(rate))
        }
    }

    func setShowDanmaku(_ enabled: Bool) {
        showDanmaku = enabled
        AppPreferences.showDanmaku = enabled
        if !enabled {
            activeDanmaku.removeAll()
        }
    }

    func persistCurrentProgress() {
        guard let page = currentPage else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        currentSeconds = seconds
        lastPersistedSeconds = seconds
        libraryStore?.updateWatchRecord(video: detail.video, page: page, progressSeconds: seconds)
    }

    func sendDanmaku(session: BiliSession?) async {
        guard let page = currentPage else { return }
        guard let session, session.isLoggedIn else {
            danmakuError = "请先登录后发送弹幕"
            return
        }
        let text = danmakuInput.trimmed
        guard !text.isEmpty else { return }

        isSendingDanmaku = true
        danmakuError = nil
        defer { isSendingDanmaku = false }

        do {
            guard let bvid = detail.video.bvid else {
                danmakuError = "当前视频缺少 BV 号，暂不支持发送弹幕"
                return
            }
            try await BiliAPIClient.shared.sendDanmaku(
                session: session,
                bvid: bvid,
                cid: page.cid,
                text: text,
                progressMS: Int(max(currentSeconds, 0) * 1000)
            )
            danmakuInput = ""
        } catch {
            danmakuError = error.localizedDescription
        }
    }

    private func resumeProgress(for page: BiliVideoPage) -> Double? {
        guard let bvid = detail.video.bvid else { return nil }
        if selectedPageIndex == initialPageIndex, let initialStartAtSeconds, initialStartAtSeconds > 0 {
            return initialStartAtSeconds
        }
        return libraryStore?.resumeProgress(for: bvid, cid: page.cid)
    }

    private func configurePlayer(with url: URL, startAtSeconds: Double?) {
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

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            await self?.resumePlayback(at: startAtSeconds)
        }
    }

    private func resumePlayback(at startAtSeconds: Double?) {
        if let startAtSeconds, startAtSeconds > 0 {
            player.seek(to: CMTime(seconds: startAtSeconds, preferredTimescale: 600))
        }
        player.playImmediately(atRate: Float(playbackRate))
    }

    private func configureTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleTimeUpdate(seconds: time.seconds)
            }
        }
    }

    private func configureEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, notification.object as AnyObject? === self.player.currentItem else { return }
                self.persistCurrentProgress()
                guard AppPreferences.autoPlayNext, self.canGoToNextPage else { return }
                await self.goToNextPage()
            }
        }
    }

    private func handleTimeUpdate(seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }

        if seconds + 1 < lastObservedSeconds {
            resetDanmakuCursor(for: seconds)
        }

        currentSeconds = seconds
        lastObservedSeconds = seconds

        if seconds - lastPersistedSeconds >= 5 {
            persistCurrentProgress()
        }

        guard showDanmaku else { return }

        while nextDanmakuIndex < danmakuItems.count, danmakuItems[nextDanmakuIndex].time <= seconds {
            emitDanmaku(danmakuItems[nextDanmakuIndex])
            nextDanmakuIndex += 1
        }
    }

    private func emitDanmaku(_ item: BiliDanmakuItem) {
        let active = ActiveDanmakuItem(item: item, lane: nextDanmakuLane)
        nextDanmakuLane = (nextDanmakuLane + 1) % 6
        activeDanmaku.append(active)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.activeDanmaku.removeAll { $0.id == active.id }
        }
    }

    private func resetDanmakuCursor(for seconds: Double) {
        nextDanmakuIndex = danmakuItems.firstIndex(where: { $0.time >= seconds }) ?? danmakuItems.count
        activeDanmaku.removeAll()
    }

    func tearDown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
    }
}

struct PlayerView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel: PlayerViewModel

    init(detail: BiliVideoDetail, initialPageIndex: Int, startAtSeconds: Double? = nil) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(detail: detail, initialPageIndex: initialPageIndex, startAtSeconds: startAtSeconds))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    VideoPlayer(player: viewModel.player)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if viewModel.showDanmaku {
                        DanmakuOverlayView(items: viewModel.activeDanmaku)
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.detail.video.title)
                        .font(.title3.bold())

                    if let page = viewModel.currentPage {
                        Text(page.label)
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                    }

                    if let quality = viewModel.playback?.qualityDescription {
                        Label(quality, systemImage: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let page = viewModel.currentPage {
                        Text(BiliFormat.progressText(viewModel.currentSeconds, total: page.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isLoading {
                    ProgressView("正在获取播放地址")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("播放失败", systemImage: "play.slash.fill", description: Text(errorMessage))
                }

                playbackControls
                danmakuControls

                if !viewModel.detail.pages.isEmpty {
                    pageSwitcher
                }

                if let pageURL = viewModel.detail.video.pageURL {
                    Link(destination: pageURL) {
                        Label("在 Safari 中打开原视频页", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("播放")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.attachLibrary(libraryStore)
            await viewModel.loadCurrentPage()
        }
        .onDisappear {
            viewModel.persistCurrentProgress()
            viewModel.tearDown()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            viewModel.persistCurrentProgress()
        }
    }

    private var playbackControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放控制")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.goToPreviousPage() }
                } label: {
                    Label("上一 P", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToPreviousPage)

                Button {
                    viewModel.player.playImmediately(atRate: Float(viewModel.playbackRate))
                } label: {
                    Label("播放", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.player.pause()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.goToNextPage() }
                } label: {
                    Label("下一 P", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canGoToNextPage)
            }

            Picker("倍速", selection: $viewModel.playbackRate) {
                Text("0.75x").tag(0.75)
                Text("1.0x").tag(1.0)
                Text("1.25x").tag(1.25)
                Text("1.5x").tag(1.5)
                Text("2.0x").tag(2.0)
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.playbackRate) { _, newValue in
                viewModel.setPlaybackRate(newValue)
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var danmakuControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("弹幕")
                    .font(.headline)
                Spacer()
                Toggle("显示弹幕", isOn: Binding(
                    get: { viewModel.showDanmaku },
                    set: { viewModel.setShowDanmaku($0) }
                ))
                .labelsHidden()
            }

            HStack(spacing: 10) {
                TextField("发送弹幕", text: $viewModel.danmakuInput)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        await viewModel.sendDanmaku(session: authStore.session)
                    }
                } label: {
                    if viewModel.isSendingDanmaku {
                        ProgressView()
                    } else {
                        Text("发送")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.danmakuInput.trimmed.isEmpty)
            }

            if let danmakuError = viewModel.danmakuError {
                Text(danmakuError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(authStore.isLoggedIn ? "已登录，可发送普通弹幕。" : "登录后可发送弹幕，未登录时仍可查看弹幕。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var pageSwitcher: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("切换分 P")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.detail.pages.enumerated()), id: \.offset) { index, page in
                        Button {
                            Task {
                                await viewModel.selectPage(at: index)
                            }
                        } label: {
                            Text(page.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    index == viewModel.selectedPageIndex ? AppTheme.accent : AppTheme.card,
                                    in: Capsule()
                                )
                                .foregroundStyle(index == viewModel.selectedPageIndex ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
