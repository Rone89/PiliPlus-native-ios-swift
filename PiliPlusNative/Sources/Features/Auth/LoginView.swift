import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

@MainActor
final class LoginViewModel: ObservableObject {
    @Published private(set) var qrInfo: QRCodeLoginInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var countdown = 0
    @Published var statusText = "正在准备扫码登录"
    @Published var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    deinit {
        pollTask?.cancel()
    }

    func start(authStore: AuthStore) async {
        guard qrInfo == nil else { return }
        await refresh(authStore: authStore)
    }

    func refresh(authStore: AuthStore) async {
        pollTask?.cancel()
        isLoading = true
        errorMessage = nil
        statusText = "正在生成二维码"
        defer { isLoading = false }

        do {
            let info = try await BiliAPIClient.shared.beginQRCodeLogin()
            qrInfo = info
            countdown = 180
            statusText = "请使用 bilibili 官方 App 扫码确认"
            beginPolling(info: info, authStore: authStore)
        } catch {
            errorMessage = error.localizedDescription
            statusText = "二维码加载失败"
        }
    }

    private func beginPolling(info: QRCodeLoginInfo, authStore: AuthStore) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            let expiresAt = Date().addingTimeInterval(180)

            while !Task.isCancelled {
                let remaining = max(0, Int(expiresAt.timeIntervalSinceNow.rounded()))
                await MainActor.run {
                    self.countdown = remaining
                }

                if remaining <= 0 {
                    await MainActor.run {
                        self.statusText = "二维码已过期，请刷新"
                    }
                    break
                }

                do {
                    let result = try await BiliAPIClient.shared.pollQRCodeLogin(authCode: info.authCode)
                    switch result.status {
                    case .pending:
                        await MainActor.run { self.statusText = result.message }
                    case .scanned:
                        await MainActor.run { self.statusText = result.message }
                    case .confirmed:
                        if let session = result.session {
                            await authStore.completeLogin(session: session)
                        }
                        await MainActor.run { self.statusText = result.message }
                        return
                    case .expired:
                        await MainActor.run {
                            self.statusText = result.message
                            self.countdown = 0
                        }
                        return
                    case .failed:
                        await MainActor.run {
                            self.statusText = result.message
                            self.errorMessage = result.message
                        }
                        return
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.statusText = "登录轮询失败"
                    }
                    return
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("使用 bilibili 官方 App 扫码登录")
                        .font(.headline)

                    if let info = viewModel.qrInfo {
                        QRCodeImageView(content: info.url)
                            .frame(width: 220, height: 220)
                            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.top, 8)

                        Text("剩余有效时间：\(viewModel.countdown) 秒")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Text(viewModel.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Text(info.url)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal)
                    } else if viewModel.isLoading {
                        ProgressView("正在生成二维码")
                            .padding(.vertical, 60)
                    } else if let errorMessage = viewModel.errorMessage {
                        ContentUnavailableView("二维码加载失败", systemImage: "qrcode", description: Text(errorMessage))
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await viewModel.refresh(authStore: authStore)
                            }
                        } label: {
                            Label("刷新二维码", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("关闭") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    Text("扫码成功后会同步当前账号资料、动态和私信未读数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("扫码登录")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.start(authStore: authStore)
            }
            .onReceive(authStore.$session) { session in
                if session?.isLoggedIn == true {
                    dismiss()
                }
            }
        }
    }
}

private struct QRCodeImageView: View {
    let content: String

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        if let image = generateQRCode(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(18)
        } else {
            ContentUnavailableView("二维码生成失败", systemImage: "qrcode")
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
