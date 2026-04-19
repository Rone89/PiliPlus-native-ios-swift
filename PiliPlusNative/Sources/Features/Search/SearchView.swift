import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var results: [BiliVideo] = []
    @Published private(set) var trending: [BiliTrendingKeyword] = []
    @Published private(set) var history: [String] = SearchHistoryStore.load()
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private var currentKeyword = ""
    private var page = 1
    private var hasMore = true

    func loadTrendingIfNeeded() async {
        guard trending.isEmpty else { return }
        do {
            trending = try await BiliAPIClient.shared.fetchTrending()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(_ keyword: String) async {
        let trimmed = keyword.trimmed
        guard !trimmed.isEmpty else {
            results = []
            currentKeyword = ""
            errorMessage = nil
            return
        }

        currentKeyword = trimmed
        page = 1
        hasMore = true
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let items = try await BiliAPIClient.shared.searchVideos(keyword: trimmed, page: page)
            results = items
            page += 1
            hasMore = !items.isEmpty
            SearchHistoryStore.save(trimmed)
            history = SearchHistoryStore.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(after video: BiliVideo) async {
        guard !currentKeyword.isEmpty, hasMore, !isLoading, !isLoadingMore, results.last?.id == video.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let items = try await BiliAPIClient.shared.searchVideos(keyword: currentKeyword, page: page)
            results.append(contentsOf: items)
            page += 1
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeHistory(_ keyword: String) {
        SearchHistoryStore.remove(keyword)
        history = SearchHistoryStore.load()
    }

    func clearHistory() {
        SearchHistoryStore.clear()
        history = SearchHistoryStore.load()
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var query = ""

    var body: some View {
        Group {
            if query.trimmed.isEmpty && viewModel.results.isEmpty {
                List {
                    if !viewModel.history.isEmpty {
                        Section {
                            ForEach(viewModel.history, id: \.self) { item in
                                HStack {
                                    Button {
                                        query = item
                                        Task { await viewModel.search(item) }
                                    } label: {
                                        Label(item, systemImage: "clock.arrow.circlepath")
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        viewModel.removeHistory(item)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Button("清空历史", role: .destructive) {
                                viewModel.clearHistory()
                            }
                        } header: {
                            Text("搜索历史")
                        }
                    }

                    if !viewModel.trending.isEmpty {
                        Section("搜索热词") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                                ForEach(viewModel.trending) { item in
                                    Button {
                                        query = item.keyword
                                        Task { await viewModel.search(item.keyword) }
                                    } label: {
                                        Text(item.displayText)
                                            .font(.subheadline.weight(.medium))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .padding(.horizontal, 10)
                                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else if viewModel.isLoading && viewModel.results.isEmpty {
                ProgressView("正在搜索")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.results.isEmpty {
                ContentUnavailableView("搜索失败", systemImage: "magnifyingglass", description: Text(errorMessage))
            } else if viewModel.results.isEmpty {
                ContentUnavailableView("没有找到结果", systemImage: "text.magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(viewModel.results) { video in
                            NavigationLink {
                                VideoDetailView(bvid: video.bvid)
                            } label: {
                                VideoCardView(video: video)
                            }
                            .buttonStyle(.plain)
                            .task {
                                await viewModel.loadMoreIfNeeded(after: video)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 12)
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索视频标题或 BV 号")
        .onSubmit(of: .search) {
            Task {
                await viewModel.search(query)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("搜索") {
                    Task {
                        await viewModel.search(query)
                    }
                }
                .disabled(query.trimmed.isEmpty)
            }
        }
        .task {
            await viewModel.loadTrendingIfNeeded()
        }
    }
}

