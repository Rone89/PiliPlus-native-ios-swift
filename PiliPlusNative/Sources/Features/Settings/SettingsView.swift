import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showClearHistoryConfirmation = false
    @State private var showClearFavoritesConfirmation = false
    @State private var playbackRate = AppPreferences.playbackRate
    @State private var autoPlayNext = AppPreferences.autoPlayNext

    private var versionText: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        List {
            Section("关于") {
                LabeledContent("应用版本", value: versionText)
                LabeledContent("实现方式", value: "SwiftUI + URLSession + XcodeGen")
                LabeledContent("当前定位", value: "原生 iOS 可用版")
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

                Picker("默认倍速", selection: $playbackRate) {
                    Text("0.75x").tag(0.75)
                    Text("1.0x").tag(1.0)
                    Text("1.25x").tag(1.25)
                    Text("1.5x").tag(1.5)
                    Text("2.0x").tag(2.0)
                }
            }

            Section("当前已支持") {
                Text("推荐、热门、搜索、搜索建议、BV/链接直达、UP 主主页、视频详情、评论区与回复、本地收藏、继续播放、观看历史、倍速控制、自动播放下一 P，以及 GitHub Actions unsigned IPA 发布流程。")
            }

            Section("后续可继续补完") {
                Text("登录、动态、私信、弹幕、缓存下载、账号同步等功能可以继续在当前原生架构上扩展。")
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
