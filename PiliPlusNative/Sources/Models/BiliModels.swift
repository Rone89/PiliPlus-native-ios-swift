import Foundation

struct BiliVideoStats: Hashable, Codable {
    let plays: String
    let danmaku: String?
    let likes: String?
}

struct BiliOwner: Hashable, Codable {
    let name: String
    let mid: Int?
}

struct BiliVideo: Identifiable, Hashable, Codable {
    let bvid: String
    let aid: Int?
    let title: String
    let coverURL: URL?
    let duration: Int
    let owner: BiliOwner
    let stats: BiliVideoStats
    let descriptionText: String
    let publishedAt: Int?
    let firstCID: Int?

    var id: String { bvid }
    var pageURL: URL? { URL(string: "https://www.bilibili.com/video/\(bvid)") }

    init(
        bvid: String,
        aid: Int?,
        title: String,
        coverURL: URL?,
        duration: Int,
        owner: BiliOwner,
        stats: BiliVideoStats,
        descriptionText: String,
        publishedAt: Int?,
        firstCID: Int?
    ) {
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.coverURL = coverURL
        self.duration = duration
        self.owner = owner
        self.stats = stats
        self.descriptionText = descriptionText
        self.publishedAt = publishedAt
        self.firstCID = firstCID
    }

    init?(json: [String: Any]) {
        let bvid = json.string("bvid") ?? json.string("goto_id")
        guard let bvid, !bvid.isEmpty else { return nil }

        let ownerJSON = json.dictionary("owner")
        let argsJSON = json.dictionary("args")
        let title = BiliFormat.plainText(json.string("title") ?? json.string("share_copy") ?? "未命名视频")
        let ownerName = BiliFormat.plainText(
            ownerJSON?.string("name") ??
            ownerJSON?.string("uname") ??
            argsJSON?.string("up_name") ??
            json.string("author") ??
            "未知 UP"
        )

        let statsJSON = json.dictionary("stat") ?? json.dictionary("stats")
        let aid = BiliFormat.intValue(json["aid"] ?? json["id"] ?? json["param"])
        let firstCID = BiliFormat.intValue(json["cid"])
        let duration = BiliFormat.parseDuration(json["duration"])
        let plays = BiliFormat.countText(statsJSON?["view"] ?? json["play"]) ?? "--"
        let danmaku = BiliFormat.countText(statsJSON?["danmaku"] ?? json["video_review"] ?? json["danmaku"])
        let likes = BiliFormat.countText(statsJSON?["like"] ?? json["like"])
        let desc = BiliFormat.plainText(json.string("desc") ?? json.string("description"))
        let publishedAt = BiliFormat.intValue(json["pubdate"] ?? json["pub_time"] ?? json["ctime"])
        let ownerMid = BiliFormat.intValue(ownerJSON?["mid"] ?? argsJSON?["up_id"])

        self.init(
            bvid: bvid,
            aid: aid,
            title: title,
            coverURL: BiliFormat.normalizeURL(json.string("pic") ?? json.string("cover")),
            duration: duration,
            owner: BiliOwner(name: ownerName, mid: ownerMid),
            stats: BiliVideoStats(plays: plays, danmaku: danmaku, likes: likes),
            descriptionText: desc,
            publishedAt: publishedAt,
            firstCID: firstCID
        )
    }
}

struct BiliVideoPage: Identifiable, Hashable, Codable {
    let cid: Int
    let page: Int
    let title: String
    let duration: Int

    var id: Int { cid }

    var label: String {
        if title.isEmpty {
            return "P\(page)"
        }
        return "P\(page) \(title)"
    }

    init?(json: [String: Any]) {
        guard let cid = BiliFormat.intValue(json["cid"]) else { return nil }
        self.cid = cid
        self.page = BiliFormat.intValue(json["page"]) ?? 1
        self.title = BiliFormat.plainText(json.string("part"))
        self.duration = BiliFormat.intValue(json["duration"]) ?? 0
    }
}

struct BiliVideoDetail {
    let video: BiliVideo
    let pages: [BiliVideoPage]
    let related: [BiliVideo]
}

struct BiliPlayback {
    let streamURL: URL
    let qualityDescription: String
}

struct BiliTrendingKeyword: Identifiable, Hashable {
    let keyword: String
    let displayText: String

    var id: String { keyword }
}

struct BiliComment: Identifiable, Hashable {
    let id: Int
    let authorName: String
    let avatarURL: URL?
    let message: String
    let likeCount: String?
    let replyCount: Int
    let publishedAt: Int?

    init?(json: [String: Any]) {
        guard let id = BiliFormat.intValue(json["rpid"]) else { return nil }
        let member = json.dictionary("member")
        let content = json.dictionary("content")
        self.id = id
        self.authorName = BiliFormat.plainText(member?.string("uname") ?? "匿名用户")
        self.avatarURL = BiliFormat.normalizeURL(member?.string("avatar"))
        self.message = BiliFormat.plainText(content?.string("message"))
        self.likeCount = BiliFormat.countText(json["like"])
        self.replyCount = BiliFormat.intValue(json["rcount"] ?? json["count"]) ?? 0
        self.publishedAt = BiliFormat.intValue(json["ctime"])
    }
}

struct BiliCommentPage {
    let comments: [BiliComment]
    let nextOffset: String?
    let isEnd: Bool
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        switch self[key] {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func array(_ key: String) -> [[String: Any]] {
        self[key] as? [[String: Any]] ?? []
    }
}
