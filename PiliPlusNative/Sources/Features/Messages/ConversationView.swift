import SwiftUI

@MainActor
final class ConversationViewModel: ObservableObject {
    @Published private(set) var messages: [BiliPrivateMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published var draft = ""

    let sessionPreview: BiliPrivateSession

    init(sessionPreview: BiliPrivateSession) {
        self.sessionPreview = sessionPreview
    }

    func loadIfNeeded(session: BiliSession?) async {
        guard messages.isEmpty else { return }
        await refresh(session: session)
    }

    func refresh(session: BiliSession?) async {
        guard let session else {
            messages = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await BiliAPIClient.shared.fetchPrivateMessages(session: session, talkerID: sessionPreview.talkerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(session: BiliSession?) async {
        guard let session else {
            errorMessage = "请先登录"
            return
        }
        let text = draft.trimmed
        guard !text.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            try await BiliAPIClient.shared.sendPrivateMessage(session: session, receiverID: sessionPreview.talkerID, text: text)
            draft = ""
            await refresh(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ConversationView: View {
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel: ConversationViewModel

    init(sessionPreview: BiliPrivateSession) {
        _viewModel = StateObject(wrappedValue: ConversationViewModel(sessionPreview: sessionPreview))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView("正在加载会话")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.messages.isEmpty {
                ContentUnavailableView("会话加载失败", systemImage: "ellipsis.bubble", description: Text(errorMessage))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                            }

                            if viewModel.messages.isEmpty {
                                Text("这个会话暂时没有消息")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 40)
                            }
                        }
                        .padding()
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
                .refreshable {
                    await viewModel.refresh(session: authStore.session)
                    await authStore.sync()
                }
            }
        }
        .navigationTitle(viewModel.sessionPreview.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField("发送一条私信", text: $viewModel.draft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task {
                            await viewModel.send(session: authStore.session)
                        }
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                        } else {
                            Text("发送")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.draft.trimmed.isEmpty)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .task {
            await viewModel.loadIfNeeded(session: authStore.session)
        }
    }
}

private struct MessageBubble: View {
    let message: BiliPrivateMessage

    var body: some View {
        HStack {
            if message.isSelf {
                Spacer(minLength: 50)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isSelf ? .white : .primary)

                if let timestamp = message.timestamp,
                   let dateText = BiliFormat.absoluteDate(TimeInterval(timestamp)) {
                    Text(dateText)
                        .font(.caption2)
                        .foregroundStyle(message.isSelf ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                message.isSelf ? AppTheme.accent : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

            if !message.isSelf {
                Spacer(minLength: 50)
            }
        }
    }
}
