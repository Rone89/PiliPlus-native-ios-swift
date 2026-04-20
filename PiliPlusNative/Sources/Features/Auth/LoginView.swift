import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum LoginMethod: String, CaseIterable, Identifiable {
    case qrcode
    case sms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qrcode:
            return "扫码"
        case .sms:
            return "短信"
        }
    }
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published private(set) var qrInfo: QRCodeLoginInfo?
    @Published private(set) var smsInfo: SMSCodeLoginInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var countdown = 0
    @Published var statusText = "正在准备登录"
    @Published var errorMessage: String?
    @Published var selectedMethod: LoginMethod = .qrcode
    @Published var countryCode = "86"
    @Published var phoneNumber = ""
    @Published var smsCode = ""
    @Published var isSendingSMSCode = false
    @Published var isLoggingInWithSMS = false

    private var pollTask: Task<Void, Never>?
    private var suspendedQRCodeInfo: QRCodeLoginInfo?

    deinit {
        pollTask?.cancel()
    }

    func start(authStore: AuthStore) async {
        guard selectedMethod == .qrcode, qrInfo == nil else { return }
        await refreshQRCode(authStore: authStore)
    }

    func switchMethod(to method: LoginMethod) {
        selectedMethod = method
        errorMessage = nil
        if method == .qrcode {
            statusText = qrInfo == nil ? "正在准备扫码登录" : "请使用 bilibili 官方 App 扫码确认"
        } else {
            statusText = smsInfo == nil ? "请输入手机号并获取验证码" : "验证码已发送，请输入短信验证码"
        }
    }

    func refreshQRCode(authStore: AuthStore) async {
        pollTask?.cancel()
        suspendedQRCodeInfo = nil
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

    func sendSMSCode() async {
        isSendingSMSCode = true
        errorMessage = nil
        statusText = "正在发送验证码"
        defer { isSendingSMSCode = false }

        do {
            let info = try await BiliAPIClient.shared.sendSMSCode(countryCode: countryCode, phone: phoneNumber)
            smsInfo = info
            phoneNumber = info.telephone
            countryCode = info.countryCode
            statusText = "验证码已发送，请输入短信验证码"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "验证码发送失败"
        }
    }

    func loginWithSMS(authStore: AuthStore) async {
        guard let smsInfo else {
            errorMessage = "请先获取验证码"
            return
        }

        isLoggingInWithSMS = true
        errorMessage = nil
        statusText = "正在使用验证码登录"
        defer { isLoggingInWithSMS = false }

        do {
            let session = try await BiliAPIClient.shared.loginBySMS(
                countryCode: smsInfo.countryCode,
                phone: smsInfo.telephone,
                code: smsCode,
                captchaKey: smsInfo.captchaKey
            )
            await authStore.completeLogin(session: session)
            statusText = "短信登录成功"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "短信登录失败"
        }
    }

    func pauseQRCodePolling() {
        guard let qrInfo else { return }
        suspendedQRCodeInfo = qrInfo
        pollTask?.cancel()
    }

    func resumeQRCodePollingIfNeeded(authStore: AuthStore) async {
        guard selectedMethod == .qrcode else { return }
        guard authStore.currentSessionMID == nil else { return }
        guard let info = suspendedQRCodeInfo ?? qrInfo else { return }
        suspendedQRCodeInfo = nil
        beginPolling(info: info, authStore: authStore)
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
                    case .pending, .scanned:
                        await MainActor.run {
                            self.statusText = result.message
                        }
                    case .confirmed:
                        if let session = result.session {
                            await authStore.completeLogin(session: session)
                        }
                        await MainActor.run {
                            self.statusText = result.message
                        }
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
                        guard self.suspendedQRCodeInfo == nil else { return }
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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authStore: AuthStore

    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("登录方式", selection: Binding(
                        get: { viewModel.selectedMethod },
                        set: { viewModel.switchMethod(to: $0) }
                    )) {
                        ForEach(LoginMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if viewModel.selectedMethod == .qrcode {
                        qrLoginSection
                    } else {
                        smsLoginSection
                    }
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.start(authStore: authStore)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background, .inactive:
                    viewModel.pauseQRCodePolling()
                case .active:
                    Task {
                        await viewModel.resumeQRCodePollingIfNeeded(authStore: authStore)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: authStore.currentSessionMID) { _, currentMID in
                if currentMID != nil {
                    dismiss()
                }
            }
        }
    }

    private var qrLoginSection: some View {
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
                        await viewModel.refreshQRCode(authStore: authStore)
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
    }

    private var smsLoginSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通过手机号获取验证码登录")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    TextField("区号", text: $viewModel.countryCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    TextField("手机号", text: $viewModel.phoneNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    TextField("验证码", text: $viewModel.smsCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task {
                            await viewModel.sendSMSCode()
                        }
                    } label: {
                        if viewModel.isSendingSMSCode {
                            ProgressView()
                                .frame(width: 96)
                        } else {
                            Text(viewModel.smsInfo == nil ? "获取验证码" : "重新获取")
                                .frame(width: 96)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.phoneNumber.trimmed.isEmpty)
                }
            }
            .padding(.horizontal)

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let smsInfo = viewModel.smsInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前号码：+\(smsInfo.countryCode) \(smsInfo.telephone)")
                    Text("captcha_key：\(smsInfo.captchaKey)")
                        .textSelection(.enabled)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.loginWithSMS(authStore: authStore)
                    }
                } label: {
                    if viewModel.isLoggingInWithSMS {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("验证码登录", systemImage: "message.badge")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.smsCode.trimmed.isEmpty || viewModel.smsInfo == nil)

                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Text("如果接口返回风控或极验校验，当前版本会直接提示失败，后续再补完整验证流。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
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
