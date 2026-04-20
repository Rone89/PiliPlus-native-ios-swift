import Foundation

struct BiliSessionCookie: Codable, Hashable {
    let name: String
    let value: String
}

struct BiliSession: Codable, Hashable, Identifiable {
    let accessToken: String?
    let refreshToken: String?
    let cookies: [BiliSessionCookie]

    var id: String {
        if let mid {
            return "\(mid)"
        }
        return cookieHeader
    }

    var isLoggedIn: Bool {
        cookieValue(named: "SESSDATA") != nil
    }

    var mid: Int? {
        guard let raw = cookieValue(named: "DedeUserID") else { return nil }
        return Int(raw)
    }

    var csrf: String {
        cookieValue(named: "bili_jct") ?? ""
    }

    var cookieHeader: String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func cookieValue(named name: String) -> String? {
        cookies.first(where: { $0.name == name })?.value
    }

    static func from(tokenInfo: [String: Any], cookieInfo: [[String: Any]]) -> BiliSession {
        let cookies = cookieInfo.compactMap { item -> BiliSessionCookie? in
            guard let name = item["name"] as? String,
                  let value = item["value"] as? String else {
                return nil
            }
            return BiliSessionCookie(name: name, value: value)
        }

        return BiliSession(
            accessToken: tokenInfo["access_token"] as? String,
            refreshToken: tokenInfo["refresh_token"] as? String,
            cookies: cookies
        )
    }
}

struct BiliCurrentUser: Codable, Hashable {
    let mid: Int
    let name: String
    let faceURL: URL?
    let levelText: String?
    let coinsText: String?
    let followingText: String?
    let followersText: String?
}

struct BiliUnreadState: Codable, Hashable {
    let privateUnread: Int
    let dynamicUnread: Int
    let replyUnread: Int
    let atUnread: Int
    let likeUnread: Int
    let systemUnread: Int

    static let empty = BiliUnreadState(
        privateUnread: 0,
        dynamicUnread: 0,
        replyUnread: 0,
        atUnread: 0,
        likeUnread: 0,
        systemUnread: 0
    )
}

enum BiliNotificationKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case reply
    case mention
    case like
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply:
            return "回复我的"
        case .mention:
            return "@ 我的"
        case .like:
            return "收到的赞"
        case .system:
            return "系统通知"
        }
    }
}

struct BiliNotificationItem: Identifiable, Hashable {
    let id: String
    let kind: BiliNotificationKind
    let userMid: Int?
    let title: String
    let subtitle: String
    let detail: String?
    let avatarURL: URL?
    let imageURL: URL?
    let timestamp: Int?
    let rawCursor: Int?
}

struct BiliNotificationPage {
    let items: [BiliNotificationItem]
    let nextCursor: Int?
    let nextCursorTime: Int?
}

struct QRCodeLoginInfo: Hashable {
    let authCode: String
    let url: String
}

enum QRCodeLoginStatus {
    case pending
    case scanned
    case confirmed
    case expired
    case failed
}

struct QRCodeLoginResult {
    let status: QRCodeLoginStatus
    let message: String
    let session: BiliSession?
}

struct BiliDynamicPost: Identifiable, Hashable {
    let id: String
    let authorName: String
    let authorMid: Int?
    let authorAvatarURL: URL?
    let commentID: Int?
    let commentType: Int?
    let text: String
    let title: String?
    let coverURL: URL?
    let imageURLs: [URL]
    let videoBVID: String?
    let publishedAt: Int?
    let kindLabel: String
    let likeCount: String?
    let commentCount: String?
    let forwardCount: String?
    let isLiked: Bool

    init?(json: [String: Any]) {
        guard let id = json.string("id_str") ?? json.string("id") else { return nil }
        let basic = json.dictionary("basic")
        let modules = json.dictionary("modules")
        let moduleAuthor = modules?.dictionary("module_author")
        let moduleDynamic = modules?.dictionary("module_dynamic")
        let moduleDesc = moduleDynamic?.dictionary("desc")
        let major = moduleDynamic?.dictionary("major")
        let moduleStat = modules?.dictionary("module_stat")

        let authorName = BiliFormat.plainText(moduleAuthor?.string("name"))
        let authorMid = BiliFormat.intValue(moduleAuthor?["mid"])
        let authorAvatarURL = BiliFormat.normalizeURL(moduleAuthor?.string("face"))
        let publishedAt = BiliFormat.intValue(moduleAuthor?["pub_ts"])
        let commentID = BiliFormat.intValue(basic?["comment_id_str"])
        let commentType = BiliFormat.intValue(basic?["comment_type"])

        let descriptionText = BiliFormat.plainText(moduleDesc?.string("text"))

        var title: String?
        var coverURL: URL?
        var imageURLs: [URL] = []
        var videoBVID: String?
        var kindLabel = "动态"
        var summaryText = descriptionText

        if let archive = major?.dictionary("archive") {
            title = BiliFormat.plainText(archive.string("title"))
            coverURL = BiliFormat.normalizeURL(archive.string("cover"))
            videoBVID = archive.string("bvid")
            kindLabel = "视频动态"
        } else if let opus = major?.dictionary("opus") {
            title = BiliFormat.plainText(opus.string("title"))
            if let summary = opus.dictionary("summary") {
                summaryText = [descriptionText, BiliFormat.plainText(summary.string("text"))]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            imageURLs = (opus.array("pics").compactMap { BiliFormat.normalizeURL($0.string("url")) })
            coverURL = imageURLs.first
            kindLabel = imageURLs.isEmpty ? "文字动态" : "图文动态"
        } else if let draw = major?.dictionary("draw") {
            imageURLs = draw.array("items").compactMap { BiliFormat.normalizeURL($0.string("src")) }
            coverURL = imageURLs.first
            kindLabel = "图片动态"
        } else if let article = major?.dictionary("article") {
            title = BiliFormat.plainText(article.string("title"))
            coverURL = BiliFormat.normalizeURL(article.string("cover"))
            kindLabel = "专栏动态"
        }

        let text = summaryText.isEmpty ? descriptionText : summaryText

        self.id = id
        self.authorName = authorName.isEmpty ? "未知用户" : authorName
        self.authorMid = authorMid
        self.authorAvatarURL = authorAvatarURL
        self.commentID = commentID
        self.commentType = commentType
        self.text = text
        self.title = title
        self.coverURL = coverURL
        self.imageURLs = imageURLs
        self.videoBVID = videoBVID
        self.publishedAt = publishedAt
        self.kindLabel = kindLabel
        self.likeCount = BiliFormat.countText(moduleStat?.dictionary("like")?["count"])
        self.commentCount = BiliFormat.countText(moduleStat?.dictionary("comment")?["count"])
        self.forwardCount = BiliFormat.countText(moduleStat?.dictionary("forward")?["count"])
        self.isLiked = (moduleStat?.dictionary("like")?["status"] as? Bool) ?? false
    }
}

struct BiliComposeDynamicResult: Hashable {
    let dynamicID: String?
}

struct BiliPrivateSession: Identifiable, Hashable {
    let talkerID: Int
    let name: String
    let avatarURL: URL?
    let previewText: String
    let unreadCount: Int
    let isPinned: Bool
    let lastTimestamp: Int?
    let maxSeqNo: Int?
    let ackSeqNo: Int?

    var id: Int { talkerID }

    init?(json: [String: Any], userCards: [Int: BiliUserCard] = [:]) {
        let talkerID = BiliFormat.intValue(json["talker_id"] ?? json["talker_uid"] ?? json["uid"])
        guard let talkerID else { return nil }

        let card = userCards[talkerID]
        let name = BiliFormat.plainText(
            json.string("talker_nick") ??
            json.string("talker_name") ??
            json.string("nick_name") ??
            card?.name ??
            "用户 \(talkerID)"
        )
        let previewText = BiliFormat.plainText(
            json.string("display_msg") ??
            BiliPrivateMessage.previewText(from: json.dictionary("last_msg")) ??
            "暂无消息"
        )

        self.talkerID = talkerID
        self.name = name.isEmpty ? "用户 \(talkerID)" : name
        self.avatarURL = BiliFormat.normalizeURL(
            json.string("talker_face") ??
            json.string("face_url") ??
            card?.faceURL?.absoluteString
        )
        self.previewText = previewText
        self.unreadCount = BiliFormat.intValue(json["unread_count"]) ?? 0
        self.isPinned = (json["is_pinned"] as? Bool) ?? (BiliFormat.intValue(json["is_pinned"] ?? json["is_top"]) == 1)
        self.lastTimestamp = BiliFormat.intValue(json["session_ts"] ?? json["timestamp"])
        self.maxSeqNo = BiliFormat.intValue(json["max_seqno"])
        self.ackSeqNo = BiliFormat.intValue(json["ack_seqno"])
    }
}

struct BiliPrivateMessage: Identifiable, Hashable {
    let id: String
    let senderMid: Int
    let receiverMid: Int?
    let text: String
    let timestamp: Int?
    let isSelf: Bool

    init?(json: [String: Any], selfMid: Int) {
        guard let senderMid = BiliFormat.intValue(json["sender_uid"] ?? json["sender_uid_str"]) else { return nil }
        let receiverMid = BiliFormat.intValue(json["receiver_id"] ?? json["receiver_id_str"])
        let timestamp = BiliFormat.intValue(json["timestamp"])
        let id = BiliFormat.intValue(json["msg_key"] ?? json["msg_seqno"] ?? json["msg_key_seqno"]) ?? Int(Date().timeIntervalSince1970 * 1000)

        let text = Self.previewText(from: json) ?? ""

        self.id = "\(id)"
        self.senderMid = senderMid
        self.receiverMid = receiverMid
        self.text = text.isEmpty ? "暂不支持显示的消息类型" : text
        self.timestamp = timestamp
        self.isSelf = senderMid == selfMid
    }

    static func previewText(from message: [String: Any]?) -> String? {
        guard let message else { return nil }
        if let contentString = message["content"] as? String {
            if let data = contentString.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return BiliFormat.plainText(object["content"] as? String ?? object["text"] as? String)
            }
            return BiliFormat.plainText(contentString)
        }

        if let messageContent = message.dictionary("content") {
            return BiliFormat.plainText(messageContent.string("content") ?? messageContent.string("text"))
        }

        return nil
    }
}

struct BiliUserCard: Hashable {
    let mid: Int
    let name: String
    let faceURL: URL?
}

struct BiliDanmakuItem: Identifiable, Hashable {
    let id: String
    let time: Double
    let text: String
    let mode: Int
    let colorValue: Int
}

struct ActiveDanmakuItem: Identifiable, Hashable {
    let id = UUID()
    let item: BiliDanmakuItem
    let lane: Int
}
