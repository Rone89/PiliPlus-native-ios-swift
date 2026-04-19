import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var items: [BiliNotificationItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var selectedKind: BiliNotificationKind = .reply

    private var nextCursor: Int?
    private var nextCursorTime: Int?
    private var hasMore = true

    func loadIfNeeded(session: BiliSession?) async {
        guard items.isEmpty else { return }
        await refresh(session: session)
    }

    func refresh(session: BiliSession?) async {
        guard session != nil else {
            items = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        nextCursor = nil
        nextCursorTime = nil
        hasMore = true
        defer { isLoading = false }

        do {
            let page = try await fetchPage(session: session, kind: selectedKind, cursor: nil, cursorTime: nil)
            items = page.items
            nextCursor = page.nextCursor
            nextCursorTime = page.nextCursorTime
            hasMore = page.nextCursor != nil || selectedKind == .like
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(session: BiliSession?, after item: BiliNotificationItem) async {
        guard let session, hasMore, !isLoading, !isLoadingMore, items.last?.id == item.id else { return }
        guard selectedKind != .like else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await fetchPage(session: session, kind: selectedKind, cursor: nextCursor, cursorTime: nextCursorTime)
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            nextCursorTime = page.nextCursorTime
            hasMore = page.nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPage(session: BiliSession?, kind: BiliNotificationKind, cursor: Int?, cursorTime: Int?) async throws -> BiliNotificationPage {
        guard let session else { return BiliNotificationPage(items: [], nextCursor: nil, nextCursorTime: nil) }
        switch kind {
        case .reply:
            return try await BiliAPIClient.shared.fetchReplyNotifications(session: session, cursor: cursor, cursorTime: cursorTime)
        case .mention:
            return try await BiliAPIClient.shared.fetchMentionNotifications(session: session, cursor: cursor, cursorTime: cursorTime)
        case .like:
            return try await BiliAPIClient.shared.fetchLikeNotifications(session: session)
        case .system:
            return try await BiliAPIClient.shared.fetchSystemNotifications(session: session, cursor: cursor)
        }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = NotificationsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("消息类型", selection: $viewModel.selectedKind) {
                ForEach(BiliNotificationKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("正在加载消息")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView("消息加载失败", systemImage: "bell", description: Text(errorMessage))
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView("暂无消息", systemImage: "bell.slash")
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            NotificationRow(item: item)
                                .task {
                                    await viewModel.loadMoreIfNeeded(session: authStore.session, after: item)
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
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await authStore.sync()
                        await viewModel.refresh(session: authStore.session)
                    }
                }
            }
        }
        .navigationTitle("消息中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await authStore.syncIfNeeded()
            await viewModel.loadIfNeeded(session: authStore.session)
        }
        .onChange(of: viewModel.selectedKind) { _, _ in
            Task {
                await viewModel.refresh(session: authStore.session)
            }
        }
    }
}

private struct NotificationRow: View {
    let item: BiliNotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let avatarURL = item.avatarURL {
                AsyncImage(url: avatarURL) { phase in
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
            } else {
                Image(systemName: item.kind == .system ? "bell.circle" : "message.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    if let timestamp = item.timestamp,
                       let relative = BiliFormat.relativeDate(timestamp) {
                        Text(relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
