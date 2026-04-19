import SwiftUI

@MainActor
final class ComposeDynamicViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    func submit(session: BiliSession?) async -> Bool {
        guard let session else {
            errorMessage = "请先登录"
            return false
        }

        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return false }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await BiliAPIClient.shared.createTextDynamic(session: session, text: trimmed)
            successMessage = "动态发布成功"
            text = ""
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct ComposeDynamicView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = ComposeDynamicViewModel()

    var onSuccess: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $viewModel.text)
                    .frame(minHeight: 220)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack {
                    Text("\(viewModel.text.count) / 1000")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let successMessage = viewModel.successMessage {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("发布动态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let succeeded = await viewModel.submit(session: authStore.session)
                            if succeeded {
                                onSuccess?()
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("发布")
                        }
                    }
                    .disabled(viewModel.text.trimmed.isEmpty || viewModel.text.count > 1000)
                }
            }
        }
    }
}
