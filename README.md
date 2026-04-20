# PiliPlus Native iOS

这是一个用 `SwiftUI` 重写的 PiliPlus iOS 原生版本，目标是持续把原 Flutter iOS 端能力迁移到原生工程，并通过 GitHub Actions 自动产出未签名 IPA。

项目参考并重构自原始开源项目 [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)，仓库中保留了 GPLv3 许可证文件。

## 当前能力

- 原生 SwiftUI 导航与界面
- 推荐 / 热门视频流
- 搜索、搜索建议、BV/av/链接直达
- 视频详情、评论、二级回复、分 P 播放
- UP 主主页与投稿列表
- 扫码登录
- 多账号基础、账号管理与切换
- 个人中心同步
- 动态流
- 动态文本发布
- 动态详情与评论互动
- 消息中心
- 私信会话、会话详情、文本发送
- 弹幕查看与发送
- 本地收藏、观看历史、继续播放
- 倍速控制、自动播放下一 P
- GitHub Actions 自动构建 unsigned IPA 并发布到 Releases

## 技术路线

- `SwiftUI` 负责界面与导航
- `URLSession` 直连 Bilibili 公共接口
- `CryptoKit` 实现 WBI 与 App 签名
- `VideoPlayer` + `AVURLAsset` 请求头处理播放
- `UserDefaults` + `Codable` 保存本地状态与账号缓存
- `XcodeGen` 在 CI 中生成 Xcode 工程

## 本地结构

- `PiliPlusNative/`：原生 iOS 源码与资源
- `project.yml`：XcodeGen 工程定义
- `.github/workflows/release.yml`：GitHub Actions 打包与 Release
- `scripts/create_unsigned_ipa.sh`：封装 unsigned IPA

`source/` 目录仅作为原 Flutter 项目的本地参考，不参与新工程构建。

## GitHub Actions 用法

1. 将当前目录内容推送到 GitHub 仓库。
2. 打开仓库的 `Actions`。
3. 运行 `Build Native iOS Release`，或推送一个 `v*` tag。
4. 构建完成后，在 `Releases` 下载 `PiliPlusNative-unsigned.ipa`。

## 说明

当前版本已经把“登录、个人中心、动态、私信、弹幕、播放、搜索、历史”串成了原生可用主链路，但仍未完全覆盖原 Flutter 项目的全部高级能力，例如更完整的动态互动、多媒体私信、离线缓存下载、更多弹幕设置与更深的账号同步策略。后续会继续按大模块补全。
