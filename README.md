# PiliPlus Native iOS

这是一个用 `SwiftUI` 重写的 PiliPlus iOS 原生版本。当前仓库的目标已经不只是演示原型，而是先交付一个可以日常浏览和播放视频的原生客户端基础版，并通过 GitHub Actions 自动产出未签名 IPA。

项目参考并重构自原始开源项目 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)，仓库中保留了 GPLv3 许可证文件。

## 当前能力

- 原生 SwiftUI 导航与界面
- 推荐视频流
- 热门视频流
- 关键词搜索
- 直接粘贴 `BV`、`av` 或 bilibili 视频链接直达详情页
- 视频详情页
- 评论区首屏与继续加载
- 评论二级回复查看
- 分 P 播放
- UP 主主页与投稿列表
- 搜索建议
- 扫码登录
- 个人中心同步
- 动态流
- 动态文本发布
- 私信会话与会话详情
- 消息中心
- 本地收藏
- 本地观看历史
- 继续播放与播放进度恢复
- 播放倍速控制
- 自动播放下一 P
- 弹幕查看与发送
- GitHub Actions 自动构建 unsigned IPA 并发布到 Releases

## 技术路线

- `SwiftUI` 负责界面与导航
- `URLSession` 直连 Bilibili 公共接口
- `CryptoKit` 实现 WBI 签名
- `VideoPlayer` + 带请求头的 `AVURLAsset` 处理播放
- `UserDefaults` + `Codable` 保存本地收藏与观看历史
- `XcodeGen` 在 CI 中生成 Xcode 工程，避免手写 `.pbxproj`

## 本地结构

- `PiliPlusNative/`：原生 iOS 源码与资源
- `project.yml`：XcodeGen 工程定义
- `.github/workflows/release.yml`：GitHub Actions 打包与 Release
- `scripts/create_unsigned_ipa.sh`：将 `.xcarchive` 手工封装成 unsigned IPA

`source/` 目录只作为原 Flutter 项目的本地参考，不参与新工程构建。

## GitHub Actions 用法

1. 把当前目录内容推送到你的 GitHub 仓库。
2. 打开仓库的 `Actions`。
3. 运行 `Build Native iOS Release` 工作流，或者推送一个 `v*` tag。
4. 构建完成后，直接在 `Releases` 下载 `PiliPlusNative-unsigned.ipa`。

## 说明

当前版本优先补齐“可浏览、可搜索、可播放、可留存本地状态”的主链路，暂未覆盖原 Flutter 项目的全部高级功能，例如登录、动态、私信、弹幕、缓存下载和多账号同步。后续可以继续在现有原生架构上扩展。
