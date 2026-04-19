import SwiftUI

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published private(set) var detail: BiliVideoDetail?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let bvid: String

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
        defer { isLoading = false }

        do {
            detail = try await BiliAPIClient.shared.fetchVideoDetail(bvid: bvid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VideoDetailView: View {
    @StateObject private var viewModel: VideoDetailViewModel
    @State private var selectedPageIndex = 0

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
                                Label(detail.video.owner.name, systemImage: "person.crop.circle")
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

                            if !detail.video.descriptionText.isEmpty {
                                Text(detail.video.descriptionText)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !detail.pages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("分 P")
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
                    if let pageURL = detail.video.pageURL {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: pageURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
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
}

