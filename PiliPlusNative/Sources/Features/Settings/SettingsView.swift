import SwiftUI

struct SettingsView: View {
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
                LabeledContent("当前定位", value: "原生 iOS MVP")
            }

            Section("当前已支持") {
                Text("推荐、热门、搜索、视频详情、分 P 播放，以及 GitHub Actions unsigned IPA 发布流程。")
            }

            Section("后续可继续补完") {
                Text("登录、收藏、动态、评论、私信、历史、下载、弹幕、离线缓存等功能可以继续在当前原生架构上扩展。")
            }

            Section("相关链接") {
                Link("原 Flutter 项目", destination: URL(string: "https://github.com/bggRGjQaUbCoE/PiliPlus")!)
                Link("Bilibili 官网", destination: URL(string: "https://www.bilibili.com")!)
            }
        }
        .navigationTitle("设置")
        .listStyle(.insetGrouped)
    }
}
