import SwiftUI

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published private(set) var sessions: [BiliPrivateSession] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func loadIfNeeded(session: BiliSession?) async {
        guard sessions.isEmpty else { return }
        await refresh(session: session)
    }

    func refresh(session: BiliSession?) async {
        guard let session else {
            sessions = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sessions = try await BiliAPIClient.shared.fetchPrivateSessions(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(session: BiliSession?, sessionPreview: BiliPrivateSession) async {
        guard let session else { return }
        do {
            try await BiliAPIClient.shared.removeConversation(session: session, talkerID: sessionPreview.talkerID)
            sessions.removeAll { $0.id == sessionPreview.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePinned(session: BiliSession?, sessionPreview: BiliPrivateSession) async {
        guard let session else { return }
        do {
            try await BiliAPIClient.shared.setConversationPinned(session: session, talkerID: sessionPreview.talkerID, pinned: !sessionPreview.isPinned)
            await refresh(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MessagesView: View {
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = MessagesViewModel()
    @State private var showLoginSheet = false

    var body: some View {
        Group {
            if let session = authStore.session, session.isLoggedIn {
                if viewModel.isLoading && viewModel.sessions.isEmpty {
                    ProgressView("正在加载私信")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.sessions.isEmpty {
                    ContentUnavailableView("私信加载失败", systemImage: "bubble.left.and.bubble.right", description: Text(errorMessage))
                } else {
                    List {
                        Section("消息概览") {
                            LabeledContent("私信未读", value: "\(authStore.unreadState.privateUnread)")
                            LabeledContent("回复未读", value: "\(authStore.unreadState.replyUnread)")
                            LabeledContent("@ 我未读", value: "\(authStore.unreadState.atUnread)")
                            LabeledContent("收到的赞", value: "\(authStore.unreadState.likeUnread)")
                            LabeledContent("系统通知", value: "\(authStore.unreadState.systemUnread)")
                        }

                        Section("会话列表") {
                            if viewModel.sessions.isEmpty {
                                Text("还没有私信会话")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.sessions) { sessionPreview in
                                    NavigationLink {
                                        ConversationView(sessionPreview: sessionPreview)
                                    } label: {
                                        SessionRow(sessionPreview: sessionPreview)
                                    }
                                    .contextMenu {
                                        Button {
                                            Task {
                                                await viewModel.togglePinned(session: authStore.session, sessionPreview: sessionPreview)
                                            }
                                        } label: {
                                            Label(sessionPreview.isPinned ? "取消置顶" : "置顶会话", systemImage: sessionPreview.isPinned ? "pin.slash" : "pin")
                                        }

                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.remove(session: authStore.session, sessionPreview: sessionPreview)
                                            }
                                        } label: {
                                            Label("移除会话", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await authStore.sync()
                        await viewModel.refresh(session: authStore.session)
                    }
                }
            } else {
                RequireLoginView(
                    title: "登录后查看私信",
                    message: "首页推荐、视频详情、播放和搜索都可以直接使用；扫码登录后才会同步私信会话、消息中心和未读数。"
                ) {
                    showLoginSheet = true
                }
            }
        }
        .navigationTitle("私信")
        .toolbar {
            if authStore.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Image(systemName: "bell")
                    }
                }
            }
        }
        .task {
            await authStore.syncIfNeeded()
            await viewModel.loadIfNeeded(session: authStore.session)
        }
        .onChange(of: authStore.session) { _, session in
            Task {
                await viewModel.refresh(session: session)
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
                .environmentObject(authStore)
        }
    }
}

private struct SessionRow: View {
    let sessionPreview: BiliPrivateSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: sessionPreview.avatarURL) { phase in
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
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        Text(sessionPreview.name)
                            .font(.headline)
                        if sessionPreview.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                        }
                    }

                    Spacer()

                    if let time = sessionPreview.lastTimestamp,
                       let relative = BiliFormat.relativeDate(time) {
                        Text(relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(sessionPreview.previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if sessionPreview.unreadCount > 0 {
                    Text("未读 \(sessionPreview.unreadCount)")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
