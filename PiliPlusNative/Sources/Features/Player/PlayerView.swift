import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var playback: BiliPlayback?
    @Published private(set) var isLoading = false
    @Published private(set) var currentSeconds = 0.0
    @Published var errorMessage: String?
    @Published var selectedPageIndex: Int
    @Published var playbackRate = 1.0

    let detail: BiliVideoDetail
    let player = AVPlayer()

    private let initialPageIndex: Int
    private let initialStartAtSeconds: Double?
    private weak var libraryStore: LibraryStore?
    private var timeObserver: Any?

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
    }

    func loadCurrentPage() async {
        guard let page = currentPage else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await BiliAPIClient.shared.fetchPlayback(bvid: detail.video.bvid, cid: page.cid)
            self.playback = playback
            let resumeProgress = resumeProgress(for: page)
            currentSeconds = resumeProgress ?? 0
            configurePlayer(with: playback.streamURL, startAtSeconds: resumeProgress)
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
        if player.timeControlStatus != .paused {
            player.playImmediately(atRate: Float(rate))
        }
    }

    func persistCurrentProgress() {
        guard let page = currentPage else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        currentSeconds = seconds
        libraryStore?.updateWatchRecord(video: detail.video, page: page, progressSeconds: seconds)
    }

    private func resumeProgress(for page: BiliVideoPage) -> Double? {
        if selectedPageIndex == initialPageIndex, let initialStartAtSeconds, initialStartAtSeconds > 0 {
            return initialStartAtSeconds
        }
        return libraryStore?.resumeProgress(for: detail.video.bvid, cid: page.cid)
    }

    private func configurePlayer(with url: URL, startAtSeconds: Double?) {
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Referer": "https://www.bilibili.com/video/\(detail.video.bvid)",
                "Origin": "https://www.bilibili.com",
                "User-Agent": BiliAPIClient.userAgent
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
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            guard seconds.isFinite, seconds >= 0, let page = self.currentPage else { return }
            self.currentSeconds = seconds
            self.libraryStore?.updateWatchRecord(video: self.detail.video, page: page, progressSeconds: seconds)
        }
    }

    func tearDown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }
}

struct PlayerView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @StateObject private var viewModel: PlayerViewModel

    init(detail: BiliVideoDetail, initialPageIndex: Int, startAtSeconds: Double? = nil) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(detail: detail, initialPageIndex: initialPageIndex, startAtSeconds: startAtSeconds))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VideoPlayer(player: viewModel.player)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

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
