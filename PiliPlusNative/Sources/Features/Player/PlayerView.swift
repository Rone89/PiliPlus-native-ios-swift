import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var playback: BiliPlayback?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedPageIndex: Int

    let detail: BiliVideoDetail
    let player = AVPlayer()

    init(detail: BiliVideoDetail, initialPageIndex: Int) {
        self.detail = detail
        self.selectedPageIndex = min(max(initialPageIndex, 0), max(detail.pages.count - 1, 0))
    }

    var currentPage: BiliVideoPage? {
        detail.pages[safe: selectedPageIndex]
    }

    func loadCurrentPage() async {
        guard let page = currentPage else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playback = try await BiliAPIClient.shared.fetchPlayback(bvid: detail.video.bvid, cid: page.cid)
            self.playback = playback
            configurePlayer(with: playback.streamURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPage(at index: Int) async {
        guard selectedPageIndex != index else { return }
        selectedPageIndex = index
        await loadCurrentPage()
    }

    private func configurePlayer(with url: URL) {
        // Bilibili 视频直链通常要求 Referer/User-Agent，请求头通过 AVURLAsset 传入。
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
        player.play()
    }

    deinit {
        player.pause()
    }
}

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel

    init(detail: BiliVideoDetail, initialPageIndex: Int) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(detail: detail, initialPageIndex: initialPageIndex))
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
                }

                if viewModel.isLoading {
                    ProgressView("正在获取播放地址")
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView("播放失败", systemImage: "play.slash.fill", description: Text(errorMessage))
                }

                if !viewModel.detail.pages.isEmpty {
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
            await viewModel.loadCurrentPage()
        }
        .onDisappear {
            viewModel.player.pause()
        }
    }
}

