import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var authStore: AuthStore

    @State private var showClearHistoryConfirmation = false
    @State private var showClearFavoritesConfirmation = false
    @State private var playbackRate = AppPreferences.playbackRate
    @State private var autoPlayNext = AppPreferences.autoPlayNext
    @State private var showDanmaku = AppPreferences.showDanmaku
    @State private var recommendWithAccount = AppPreferences.recommendWithAccount

    private var versionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.11"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "21"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        List {
            Section("关于") {
                LabeledContent("应用版本", value: versionText)
                LabeledContent("实现方式", value: "SwiftUI + URLSession + XcodeGen")
                LabeledContent("当前定位", value: "原生 iOS 持续增强版")
            }

            Section("账号") {
                LabeledContent("登录状态", value: authStore.isLoggedIn ? "已登录" : "未登录")
                LabeledContent("已保存账号", value: "\(authStore.savedSessions.count)")
                if let user = authStore.currentUser {
                    LabeledContent("当前账号", value: user.name)
                    LabeledContent("UID", value: "\(user.mid)")
                }

                if !authStore.isLoggedIn {
                    Text("无需登录即可使用首页推荐、视频详情、播放和搜索。动态、私信、消息中心、弹幕发送等功能需要登录。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    AccountManagementView()
                } label: {
                    Label("打开账号管理", systemImage: "person.2")
                }

                if authStore.isLoggedIn {
                    Button("同步个人中心") {
                        Task {
                            await authStore.sync()
                        }
                    }

                    Button("退出登录", role: .destructive) {
                        Task {
                            await authStore.logout()
                        }
                    }
                }
            }

            Section("首页推荐") {
                Toggle("登录账号参与推荐", isOn: $recommendWithAccount)
                    .disabled(!authStore.isLoggedIn)
                Text(authStore.isLoggedIn ? "开启后优先带当前账号 cookie 获取首页推荐；关闭后始终走匿名推荐。" : "当前未登录，首页推荐将使用匿名模式。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("本地数据") {
                LabeledContent("收藏数量", value: "\(libraryStore.favorites.count)")
                LabeledContent("历史数量", value: "\(libraryStore.history.count)")

                Button("清空本地历史", role: .destructive) {
                    showClearHistoryConfirmation = true
                }
                .disabled(libraryStore.history.isEmpty)

                Button("清空本地收藏", role: .destructive) {
                    showClearFavoritesConfirmation = true
                }
                .disabled(libraryStore.favorites.isEmpty)
            }

            Section("播放") {
                Toggle("自动播放下一 P", isOn: $autoPlayNext)
                Toggle("默认显示弹幕", isOn: $showDanmaku)

                Picker("默认倍速", selection: $playbackRate) {
                    Text("0.75x").tag(0.75)
                    Text("1.0x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("2.0x").tag(2.0)
                }
            }

            Section("当前已支持") {
                Text("首页推荐、搜索、搜索建议、BV/链接直达、UP 主主页、扫码登录、多账号基础、个人中心同步、动态流、动态详情与评论、消息中心、私信会话与发送、弹幕查看与发送、本地收藏、继续播放、观看历史、倍速控制、自动播放下一 P，以及 GitHub Actions unsigned IPA 发布流程。")
            }

            Section("游客模式") {
                Text("游客模式下可直接使用：首页推荐、搜索、搜索建议、视频详情、播放、评论查看、本地收藏与历史。")
                Text("登录后增强：动态、消息中心、私信、弹幕发送、个人中心同步、多账号切换。")
            }

            Section("相关链接") {
                Link("原 Flutter 项目", destination: URL(string: "https://github.com/bggRGjQaUbCoE/PiliPlus")!)
                Link("Bilibili 官网", destination: URL(string: "https://www.bilibili.com")!)
            }
        }
        .navigationTitle("设置")
        .listStyle(.insetGrouped)
        .onChange(of: playbackRate) { _, newValue in
            AppPreferences.playbackRate = newValue
        }
        .onChange(of: autoPlayNext) { _, newValue in
            AppPreferences.autoPlayNext = newValue
        }
        .onChange(of: showDanmaku) { _, newValue in
            AppPreferences.showDanmaku = newValue
        }
        .onChange(of: recommendWithAccount) { _, newValue in
            AppPreferences.recommendWithAccount = newValue
        }
        .confirmationDialog("确认清空全部历史记录？", isPresented: $showClearHistoryConfirmation) {
            Button("清空历史", role: .destructive) {
                libraryStore.clearHistory()
            }
        }
        .confirmationDialog("确认清空全部本地收藏？", isPresented: $showClearFavoritesConfirmation) {
            Button("清空收藏", role: .destructive) {
                libraryStore.clearFavorites()
            }
        }
    }
}
