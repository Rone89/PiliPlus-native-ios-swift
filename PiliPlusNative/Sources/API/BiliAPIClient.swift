import CryptoKit
import Foundation
import Security

actor BiliAPIClient {
    static let shared = BiliAPIClient()

    static let webUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let appUserAgent = "Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2"

    private let apiBaseURL = URL(string: "https://api.bilibili.com")!
    private let appBaseURL = URL(string: "https://app.bilibili.com")!
    private let searchBaseURL = URL(string: "https://s.search.bilibili.com")!
    private let passBaseURL = URL(string: "https://passport.bilibili.com")!
    private let vcBaseURL = URL(string: "https://api.vc.bilibili.com")!
    private let messageBaseURL = URL(string: "https://message.bilibili.com")!

    private let appKey = "dfca71928277209b"
    private let appSecret = "b5475a8825547a4fc26c7d518eaaa02e"
    private let appTraceID = "11111111111111111111111111111111:1111111111111111:0:0"
    private let dynamicFeatures = "itemOpusStyle,listOnlyfans,onlyfansQaCard"
    private let anonymousSession: URLSession
    private let authenticatedSession: URLSession

    private var cachedMixinKey: String?
    private var cachedMixinDay: Int?

    init() {
        let anonymousConfiguration = URLSessionConfiguration.ephemeral
        anonymousConfiguration.httpCookieStorage = nil
        anonymousConfiguration.httpShouldSetCookies = false
        anonymousConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        anonymousConfiguration.urlCache = nil

        let authenticatedConfiguration = URLSessionConfiguration.ephemeral
        authenticatedConfiguration.httpCookieStorage = nil
        authenticatedConfiguration.httpShouldSetCookies = false
        authenticatedConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        authenticatedConfiguration.urlCache = nil

        self.anonymousSession = URLSession(configuration: anonymousConfiguration)
        self.authenticatedSession = URLSession(configuration: authenticatedConfiguration)
    }

    func fetchRecommended(freshIndex: Int, pageSize: Int = 20) async throws -> [BiliVideo] {
        let appVideos = try await fetchRecommendedApp(index: freshIndex, pageSize: pageSize)
        if !appVideos.isEmpty {
            return appVideos
        }

        let payload = try await request(
            path: "/x/web-interface/wbi/index/top/feed/rcmd",
            query: try await signedQuery([
                "version": "1",
                "feed_version": "V8",
                "homepage_ver": "1",
                "ps": "\(pageSize)",
                "fresh_idx": "\(max(freshIndex, 0))",
                "brush": "\(max(freshIndex, 0))",
                "fresh_type": "4"
            ]),
            headers: [
                "Referer": "https://www.bilibili.com",
                "Origin": "https://www.bilibili.com",
                "Cookie": anonymousCookieHeader
            ]
        )

        let items = payload.data.array("item")
        let videos = items.compactMap { item -> BiliVideo? in
            guard item.string("goto") == "av",
                  item["ad_info"] == nil else {
                return nil
            }
            return BiliVideo(json: item)
        }

        if !videos.isEmpty {
            return videos
        }

        return try await fetchPopular(page: max(freshIndex + 1, 1), pageSize: pageSize)
    }

    private func fetchRecommendedApp(index: Int, pageSize: Int) async throws -> [BiliVideo] {
        let params = appSignedParameters([
            "build": "2001100",
            "c_locale": "zh_CN",
            "channel": "master",
            "column": "4",
            "device": "pad",
            "device_name": "android",
            "device_type": "0",
            "disable_rcmd": "0",
            "flush": "5",
            "fnval": "976",
            "fnver": "0",
            "force_host": "2",
            "fourk": "1",
            "guidance": "0",
            "https_url_req": "0",
            "idx": "\(max(index, 0))",
            "mobi_app": "android_hd",
            "network": "wifi",
            "platform": "android",
            "player_net": "1",
            "pull": index == 0 ? "true" : "false",
            "qn": "32",
            "recsys_mode": "0",
            "s_locale": "zh_CN",
            "splash_id": "",
            "statistics": #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#,
            "voice_balance": "0"
        ])

        let payload = try await request(
            baseURL: appBaseURL,
            path: "/x/v2/feed/index",
            query: params,
            headers: anonymousAppHeaders
        )

        let items = payload.data.array("items")
        let videos = items.compactMap { item -> BiliVideo? in
            let cardGoto = item.string("card_goto")
            guard cardGoto != "ad_av",
                  cardGoto != "ad_web_s",
                  item["ad_info"] == nil else {
                return nil
            }
            return BiliVideo(json: item)
        }

        if videos.isEmpty {
            return try await fetchPopular(page: max(index + 1, 1), pageSize: pageSize)
        }
        return videos
    }

    func fetchPopular(page: Int, pageSize: Int = 20) async throws -> [BiliVideo] {
        let payload = try await request(
            path: "/x/web-interface/popular",
            query: [
                "pn": "\(page)",
                "ps": "\(pageSize)"
            ]
        )

        return payload.data.array("list").compactMap(BiliVideo.init(json:))
    }

    func fetchTrending(limit: Int = 12) async throws -> [BiliTrendingKeyword] {
        let payload = try await request(
            path: "/x/v2/search/trending/ranking",
            query: ["limit": "\(limit)"]
        )

        return payload.data.array("list").compactMap { item in
            let keyword = BiliFormat.plainText(item.string("keyword") ?? item.string("show_name"))
            guard !keyword.isEmpty else { return nil }
            let displayText = BiliFormat.plainText(item.string("show_name") ?? keyword)
            return BiliTrendingKeyword(keyword: keyword, displayText: displayText)
        }
    }

    func fetchSearchSuggestions(term: String) async throws -> [String] {
        let trimmed = term.trimmed
        guard !trimmed.isEmpty else { return [] }

        let payload = try await request(
            baseURL: searchBaseURL,
            path: "/main/suggest",
            query: [
                "term": trimmed,
                "main_ver": "v1",
                "highlight": trimmed
            ]
        )

        let suggestions = payload.data.array("tag").compactMap { item in
            BiliFormat.plainText(item.string("value") ?? item.string("name"))
        }
        return NSOrderedSet(array: suggestions).array as? [String] ?? suggestions
    }

    func searchVideos(keyword: String, page: Int, pageSize: Int = 20) async throws -> [BiliVideo] {
        let payload = try await request(
            path: "/x/web-interface/wbi/search/type",
            query: try await signedQuery([
                "search_type": "video",
                "keyword": keyword,
                "page": "\(page)",
                "page_size": "\(pageSize)",
                "platform": "pc",
                "web_location": "1430654"
            ]),
            headers: [
                "Origin": "https://search.bilibili.com",
                "Referer": "https://search.bilibili.com/video?keyword=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)",
                "Cookie": anonymousCookieHeader
            ]
        )

        return payload.data.array("result").compactMap(BiliVideo.init(json:))
    }

    func resolveBVID(from input: String) async throws -> String? {
        if let bvid = BiliInputParser.extractBVID(from: input) {
            return bvid
        }

        guard let aid = BiliInputParser.extractAID(from: input) else {
            return nil
        }

        let payload = try await fetchViewPayload(query: ["aid": "\(aid)"])
        return payload.data.string("bvid")
    }

    func beginQRCodeLogin() async throws -> QRCodeLoginInfo {
        var params = [
            "local_id": "0",
            "platform": "android",
            "mobi_app": "android_hd"
        ]
        params = appSignedParameters(params)

        let payload = try await request(
            baseURL: passBaseURL,
            path: "/x/passport-tv-login/qrcode/auth_code",
            method: "POST",
            query: params,
            headers: tvHeaders
        )

        guard let authCode = payload.data.string("auth_code"),
              let url = payload.data.string("url") else {
            throw APIError.invalidResponse("扫码登录二维码信息为空")
        }

        return QRCodeLoginInfo(authCode: authCode, url: url)
    }

    func pollQRCodeLogin(authCode: String) async throws -> QRCodeLoginResult {
        var params = [
            "auth_code": authCode,
            "local_id": "0"
        ]
        params = appSignedParameters(params)

        let payload = try await rawRequest(
            baseURL: passBaseURL,
            path: "/x/passport-tv-login/qrcode/poll",
            method: "POST",
            query: params,
            headers: tvHeaders,
            session: anonymousSession
        )

        switch payload.code {
        case 0:
            let data = payload.data.raw
            let tokenInfo = data.dictionary("token_info") ?? [:]
            let cookieInfo = data.dictionary("cookie_info")?.array("cookies") ?? []
            let session = BiliSession.from(tokenInfo: tokenInfo, cookieInfo: cookieInfo)
            return QRCodeLoginResult(status: .confirmed, message: "扫码登录成功", session: session)
        case 86039:
            return QRCodeLoginResult(status: .pending, message: "等待扫码", session: nil)
        case 86090:
            return QRCodeLoginResult(status: .scanned, message: "已扫码，请在手机上确认", session: nil)
        case 86038:
            return QRCodeLoginResult(status: .expired, message: "二维码已过期", session: nil)
        default:
            return QRCodeLoginResult(status: .failed, message: payload.message.isEmpty ? "登录失败" : payload.message, session: nil)
        }
    }

    func sendSMSCode(countryCode: String, phone: String) async throws -> SMSCodeLoginInfo {
        let cid = sanitizedCountryCode(countryCode)
        let tel = sanitizedPhone(phone)
        guard !tel.isEmpty else {
            throw APIError.invalidResponse("请输入手机号")
        }

        let timestampMS = Int(Date().timeIntervalSince1970 * 1000)
        let params = appSignedParameters([
            "build": "2001100",
            "buvid": AppPreferences.anonymousBuvid3,
            "c_locale": "zh_CN",
            "channel": "master",
            "cid": cid,
            "disable_rcmd": "0",
            "local_id": AppPreferences.anonymousBuvid3,
            "login_session_id": Self.md5("\(AppPreferences.anonymousBuvid3)\(timestampMS)"),
            "mobi_app": "android_hd",
            "platform": "android",
            "s_locale": "zh_CN",
            "statistics": #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#,
            "tel": tel,
            "ts": "\(timestampMS / 1000)"
        ])

        let payload = try await request(
            baseURL: passBaseURL,
            path: "/x/passport-login/sms/send",
            method: "POST",
            query: [:],
            body: params,
            contentType: .form,
            headers: loginHeaders
        )

        if let recaptchaURL = payload.data.string("recaptcha_url"), !recaptchaURL.isEmpty {
            throw APIError.server("当前手机号需要额外风控验证，暂不支持：\(recaptchaURL)")
        }

        guard let captchaKey = payload.data.string("captcha_key"), !captchaKey.isEmpty else {
            throw APIError.invalidResponse("验证码请求成功，但缺少 captcha_key")
        }

        return SMSCodeLoginInfo(captchaKey: captchaKey, telephone: tel, countryCode: cid)
    }

    func loginBySMS(countryCode: String, phone: String, code: String, captchaKey: String) async throws -> BiliSession {
        let cid = sanitizedCountryCode(countryCode)
        let tel = sanitizedPhone(phone)
        let smsCode = code.trimmed
        guard !tel.isEmpty, !smsCode.isEmpty else {
            throw APIError.invalidResponse("请输入手机号和验证码")
        }

        let publicKey = try await fetchLoginPublicKey()
        let encryptedRandom = try encryptRandomToken(usingPEM: publicKey)
        let params = appSignedParameters([
            "bili_local_id": AppPreferences.loginDeviceID,
            "build": "2001100",
            "buvid": AppPreferences.anonymousBuvid3,
            "c_locale": "zh_CN",
            "captcha_key": captchaKey,
            "channel": "master",
            "cid": cid,
            "code": smsCode,
            "device": "phone",
            "device_id": AppPreferences.loginDeviceID,
            "device_name": "iPhone",
            "device_platform": "iOS18iPhone",
            "disable_rcmd": "0",
            "dt": encryptedRandom,
            "from_pv": "main.my-information.my-login.0.click",
            "from_url": "bilibili://user_center/mine",
            "local_id": AppPreferences.anonymousBuvid3,
            "mobi_app": "android_hd",
            "platform": "android",
            "s_locale": "zh_CN",
            "statistics": #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#,
            "tel": tel
        ])

        let payload = try await request(
            baseURL: passBaseURL,
            path: "/x/passport-login/login/sms",
            method: "POST",
            query: [:],
            body: params,
            contentType: .form,
            headers: loginHeaders
        )

        let tokenInfo = payload.data.raw
        let cookieInfo = payload.data.dictionary("cookie_info")?.array("cookies") ?? []
        let session = BiliSession.from(tokenInfo: tokenInfo, cookieInfo: cookieInfo)
        guard session.isLoggedIn else {
            throw APIError.invalidResponse("短信登录返回成功，但没有拿到有效登录 cookie")
        }
        return session
    }

    func logout(session: BiliSession) async throws {
        let _ = try await request(
            baseURL: passBaseURL,
            path: "/login/exit/v2",
            method: "POST",
            query: [:],
            body: ["biliCSRF": session.csrf],
            contentType: .form,
            headers: authenticatedHeaders(session: session)
        )
    }

    func fetchCurrentUser(session: BiliSession) async throws -> BiliCurrentUser {
        async let navPayload = request(
            path: "/x/web-interface/nav",
            query: [:],
            headers: authenticatedHeaders(session: session)
        )

        async let statPayload = request(
            path: "/x/web-interface/nav/stat",
            query: [:],
            headers: authenticatedHeaders(session: session)
        )

        let nav = try await navPayload
        let stat = try await statPayload

        guard let mid = BiliFormat.intValue(nav.data.raw["mid"]),
              let name = nav.data.string("uname") else {
            throw APIError.invalidResponse("当前用户信息为空")
        }

        let level = nav.data.dictionary("level_info")
        let currentLevel = BiliFormat.intValue(level?["current_level"])

        return BiliCurrentUser(
            mid: mid,
            name: BiliFormat.plainText(name),
            faceURL: BiliFormat.normalizeURL(nav.data.string("face")),
            levelText: currentLevel.map { "Lv.\($0)" },
            coinsText: BiliFormat.countText(nav.data.raw["money"]),
            followingText: BiliFormat.countText(stat.data.raw["following"]),
            followersText: BiliFormat.countText(stat.data.raw["follower"])
        )
    }

    func fetchUnreadState(session: BiliSession) async throws -> BiliUnreadState {
        async let privateUnreadPayload = request(
            baseURL: vcBaseURL,
            path: "/session_svr/v1/session_svr/single_unread",
            query: [
                "build": "0",
                "mobi_app": "web",
                "unread_type": "0"
            ],
            headers: authenticatedHeaders(session: session)
        )

        async let feedUnreadPayload = request(
            path: "/x/msgfeed/unread",
            query: [
                "build": "0",
                "mobi_app": "web",
                "web_location": "333.1365"
            ],
            headers: authenticatedHeaders(session: session)
        )

        async let dynamicUnreadPayload = request(
            path: "/x/web-interface/dynamic/entrance",
            query: [:],
            headers: authenticatedHeaders(session: session)
        )

        let privateUnread = try await privateUnreadPayload
        let feedUnread = try await feedUnreadPayload
        let dynamicUnread = try await dynamicUnreadPayload

        return BiliUnreadState(
            privateUnread: BiliFormat.intValue(privateUnread.data.raw["unfollow_unread"] ?? privateUnread.data.raw["biz_msg_unfollow_unread"] ?? privateUnread.data.raw["unread_count"]) ?? 0,
            dynamicUnread: BiliFormat.intValue(dynamicUnread.data.raw["dynamic_count"] ?? dynamicUnread.data.raw["up_num"] ?? dynamicUnread.data.raw["update_num"]) ?? 0,
            replyUnread: BiliFormat.intValue(feedUnread.data.raw["reply"]) ?? 0,
            atUnread: BiliFormat.intValue(feedUnread.data.raw["at"]) ?? 0,
            likeUnread: BiliFormat.intValue(feedUnread.data.raw["like"]) ?? 0,
            systemUnread: BiliFormat.intValue(feedUnread.data.raw["sys_msg"]) ?? 0
        )
    }

    func fetchDynamicFeed(session: BiliSession, offset: String? = nil) async throws -> ([BiliDynamicPost], String?, Bool) {
        var query: [String: String] = [
            "type": "all",
            "timezone_offset": "-480",
            "features": dynamicFeatures
        ]
        if let offset, !offset.isEmpty {
            query["offset"] = offset
        }

        let payload = try await request(
            path: "/x/polymer/web-dynamic/v1/feed/all",
            query: query,
            headers: authenticatedHeaders(session: session)
        )

        let posts = payload.data.array("items").compactMap(BiliDynamicPost.init(json:))
        let nextOffset = payload.data.string("offset")
        let hasMore = (payload.data.raw["has_more"] as? Bool) ?? !posts.isEmpty
        return (posts, nextOffset, hasMore)
    }

    func fetchDynamicDetail(id: String, session: BiliSession?) async throws -> BiliDynamicPost {
        var query: [String: String] = [
            "timezone_offset": "-480",
            "id": id,
            "features": dynamicFeatures,
            "web_location": "333.1330"
        ]

        if let session, session.isLoggedIn, !session.csrf.isEmpty {
            query["csrf"] = session.csrf
        }

        let payload = try await request(
            path: "/x/polymer/web-dynamic/v1/detail",
            query: query,
            headers: session.map { authenticatedHeaders(session: $0) } ?? [:]
        )

        guard let item = payload.data.dictionary("item"),
              let post = BiliDynamicPost(json: item) else {
            throw APIError.invalidResponse("动态详情解析失败")
        }
        return post
    }

    func createTextDynamic(session: BiliSession, text: String) async throws -> BiliComposeDynamicResult {
        let payload = try await request(
            baseURL: vcBaseURL,
            path: "/dynamic_svr/v1/dynamic_svr/create",
            method: "POST",
            query: [:],
            body: [
                "dynamic_id": "0",
                "type": "4",
                "rid": "0",
                "content": text,
                "csrf_token": session.csrf,
                "csrf": session.csrf
            ],
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://t.bilibili.com/")
        )

        return BiliComposeDynamicResult(dynamicID: payload.data.string("dynamic_id") ?? payload.data.string("dyn_id_str"))
    }

    func fetchReplyNotifications(session: BiliSession, cursor: Int? = nil, cursorTime: Int? = nil) async throws -> BiliNotificationPage {
        let payload = try await request(
            path: "/x/msgfeed/reply",
            query: compactQuery([
                "id": cursor.map(String.init),
                "reply_time": cursorTime.map(String.init),
                "platform": "web",
                "mobi_app": "web",
                "build": "0",
                "web_location": "333.40164"
            ]),
            headers: authenticatedHeaders(session: session)
        )

        let items = payload.data.array("items").compactMap { item -> BiliNotificationItem? in
            let user = item.dictionary("user")
            let content = item.dictionary("item")
            let name = BiliFormat.plainText(user?.string("nickname") ?? "有人回复了你")
            let detail = BiliFormat.plainText(
                content?.string("target_reply_content") ??
                content?.string("root_reply_content") ??
                content?.string("source_content")
            )
            return BiliNotificationItem(
                id: "\(BiliFormat.intValue(item["id"]) ?? Int.random(in: 1...999999))",
                kind: .reply,
                userMid: BiliFormat.intValue(user?["mid"]),
                title: name,
                subtitle: detail.isEmpty ? "回复了你" : detail,
                detail: BiliFormat.plainText(content?.string("source_content")),
                avatarURL: BiliFormat.normalizeURL(user?.string("avatar")),
                imageURL: nil,
                timestamp: BiliFormat.intValue(item["reply_time"]),
                rawCursor: BiliFormat.intValue(item["id"])
            )
        }

        return BiliNotificationPage(
            items: items,
            nextCursor: BiliFormat.intValue(payload.data.dictionary("cursor")?["id"]),
            nextCursorTime: BiliFormat.intValue(payload.data.dictionary("cursor")?["time"])
        )
    }

    func fetchMentionNotifications(session: BiliSession, cursor: Int? = nil, cursorTime: Int? = nil) async throws -> BiliNotificationPage {
        let payload = try await request(
            path: "/x/msgfeed/at",
            query: compactQuery([
                "id": cursor.map(String.init),
                "at_time": cursorTime.map(String.init),
                "platform": "web",
                "mobi_app": "web",
                "build": "0",
                "web_location": "333.40164"
            ]),
            headers: authenticatedHeaders(session: session)
        )

        let items = payload.data.array("items").compactMap { item -> BiliNotificationItem? in
            let user = item.dictionary("user")
            let content = item.dictionary("item")
            let name = BiliFormat.plainText(user?.string("nickname") ?? "有人提到了你")
            let subtitle = BiliFormat.plainText(content?.string("source_content"))
            return BiliNotificationItem(
                id: "\(BiliFormat.intValue(item["id"]) ?? Int.random(in: 1...999999))",
                kind: .mention,
                userMid: BiliFormat.intValue(user?["mid"]),
                title: name,
                subtitle: subtitle.isEmpty ? "@ 了你" : subtitle,
                detail: nil,
                avatarURL: BiliFormat.normalizeURL(user?.string("avatar")),
                imageURL: BiliFormat.normalizeURL(content?.string("image")),
                timestamp: BiliFormat.intValue(item["at_time"]),
                rawCursor: BiliFormat.intValue(item["id"])
            )
        }

        return BiliNotificationPage(
            items: items,
            nextCursor: BiliFormat.intValue(payload.data.dictionary("cursor")?["id"]),
            nextCursorTime: BiliFormat.intValue(payload.data.dictionary("cursor")?["time"])
        )
    }

    func fetchLikeNotifications(session: BiliSession) async throws -> BiliNotificationPage {
        let payload = try await request(
            path: "/x/msgfeed/like",
            query: [
                "platform": "web",
                "mobi_app": "web",
                "build": "0",
                "web_location": "333.40164"
            ],
            headers: authenticatedHeaders(session: session)
        )

        let items = (payload.data.dictionary("latest")?.array("items") ?? []).compactMap { item -> BiliNotificationItem? in
            let users = item["users"] as? [[String: Any]] ?? []
            let content = item.dictionary("item")
            let names = users.compactMap { BiliFormat.plainText($0.string("nickname")) }.filter { !$0.isEmpty }
            let title = names.isEmpty ? "有人赞了你" : names.joined(separator: "、")
            let subtitle = BiliFormat.plainText(content?.string("title"))
            let avatarURL = BiliFormat.normalizeURL(users.first?.string("avatar"))
            let imageURL = BiliFormat.normalizeURL(content?.string("image"))
            return BiliNotificationItem(
                id: "\(BiliFormat.intValue(item["id"]) ?? Int.random(in: 1...999999))",
                kind: .like,
                userMid: nil,
                title: title,
                subtitle: subtitle.isEmpty ? "赞了你的内容" : subtitle,
                detail: nil,
                avatarURL: avatarURL,
                imageURL: imageURL,
                timestamp: BiliFormat.intValue(item["like_time"]),
                rawCursor: nil
            )
        }

        return BiliNotificationPage(items: items, nextCursor: nil, nextCursorTime: nil)
    }

    func fetchSystemNotifications(session: BiliSession, cursor: Int? = nil) async throws -> BiliNotificationPage {
        let payload = try await request(
            baseURL: messageBaseURL,
            path: "/x/sys-msg/query_notify_list",
            query: compactQuery([
                "cursor": cursor.map(String.init),
                "page_size": "20",
                "mobi_app": "web",
                "build": "0",
                "web_location": "333.40164"
            ]),
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )

        let items = payload.dataList.compactMap { item -> BiliNotificationItem? in
            let rawContent = BiliFormat.plainText(item.string("content"))
            return BiliNotificationItem(
                id: "\(BiliFormat.intValue(item["id"]) ?? Int.random(in: 1...999999))",
                kind: .system,
                userMid: nil,
                title: BiliFormat.plainText(item.string("title") ?? "系统通知"),
                subtitle: rawContent,
                detail: nil,
                avatarURL: nil,
                imageURL: nil,
                timestamp: nil,
                rawCursor: BiliFormat.intValue(item["cursor"])
            )
        }

        return BiliNotificationPage(
            items: items,
            nextCursor: items.last?.rawCursor,
            nextCursorTime: nil
        )
    }

    func fetchPrivateSessions(session: BiliSession) async throws -> [BiliPrivateSession] {
        let payload = try await request(
            baseURL: vcBaseURL,
            path: "/session_svr/v1/session_svr/get_sessions",
            query: try await signedQuery([
                "session_type": "1",
                "group_fold": "1",
                "unfollow_fold": "0",
                "sort_rule": "2",
                "build": "0",
                "mobi_app": "web"
            ]),
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )

        var sessionItems = payload.data.array("session_list")
        if sessionItems.isEmpty, let direct = payload.data.raw["sessions"] as? [[String: Any]] {
            sessionItems = direct
        }
        if sessionItems.isEmpty, let direct = payload.data.raw["session_list"] as? [[String: Any]] {
            sessionItems = direct
        }

        let talkerIDs = Array(Set(sessionItems.compactMap { BiliFormat.intValue($0["talker_id"] ?? $0["talker_uid"] ?? $0["uid"]) }))
        let userCards = try? await fetchPrivateUserCards(session: session, uids: talkerIDs)

        return sessionItems.compactMap { BiliPrivateSession(json: $0, userCards: userCards ?? [:]) }
            .sorted { ($0.lastTimestamp ?? 0) > ($1.lastTimestamp ?? 0) }
    }

    func fetchPrivateMessages(session: BiliSession, talkerID: Int, size: Int = 20) async throws -> [BiliPrivateMessage] {
        let payload = try await request(
            baseURL: vcBaseURL,
            path: "/svr_sync/v1/svr_sync/fetch_session_msgs",
            query: try await signedQuery([
                "talker_id": "\(talkerID)",
                "session_type": "1",
                "size": "\(size)",
                "sender_device_id": "1",
                "build": "0",
                "mobi_app": "web",
                "web_location": "333.1296"
            ]),
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )

        var items = payload.data.array("messages")
        if items.isEmpty, let direct = payload.data.raw["msgs"] as? [[String: Any]] {
            items = direct
        }
        if items.isEmpty, let direct = payload.data.raw["messages"] as? [[String: Any]] {
            items = direct
        }

        let selfMid = session.mid ?? 0
        let messages = items.compactMap { BiliPrivateMessage(json: $0, selfMid: selfMid) }
            .sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }

        if let maxSeqNo = items.compactMap({ BiliFormat.intValue($0["msg_seqno"] ?? $0["msg_key"]) }).max() {
            try? await acknowledgeConversation(session: session, talkerID: talkerID, ackSeqNo: maxSeqNo)
        }

        return messages
    }

    func sendPrivateMessage(session: BiliSession, receiverID: Int, text: String) async throws {
        guard let senderID = session.mid else {
            throw APIError.invalidResponse("当前账号 UID 不可用")
        }

        let devID = AppPreferences.messageDeviceID
        let timestamp = Int(Date().timeIntervalSince1970)
        let messagePayload: [String: Any] = [
            "sender_uid": senderID,
            "receiver_id": receiverID,
            "receiver_type": 1,
            "msg_type": 1,
            "msg_status": 0,
            "dev_id": devID,
            "timestamp": timestamp,
            "new_face_version": 1,
            "content": ["content": text]
        ]

        let messageData = try JSONSerialization.data(withJSONObject: messagePayload)
        guard let messageJSONString = String(data: messageData, encoding: .utf8) else {
            throw APIError.invalidResponse("私信内容编码失败")
        }

        let body: [String: Any] = [
            "msg": messageJSONString,
            "from_firework": "0",
            "build": "0",
            "mobi_app": "web",
            "csrf_token": session.csrf,
            "csrf": session.csrf
        ]

        let signSource = try await signedQuery([
            "msg": messageJSONString,
            "from_firework": "0",
            "build": "0",
            "mobi_app": "web",
            "csrf_token": session.csrf,
            "csrf": session.csrf
        ])

        let _ = try await request(
            baseURL: vcBaseURL,
            path: "/web_im/v1/web_im/send_msg",
            method: "POST",
            query: [
                "w_sender_uid": "\(senderID)",
                "w_receiver_id": "\(receiverID)",
                "w_dev_id": devID,
                "w_rid": signSource["w_rid"] ?? "",
                "wts": signSource["wts"] ?? ""
            ],
            body: body,
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )
    }

    func setConversationPinned(session: BiliSession, talkerID: Int, pinned: Bool) async throws {
        let opType = pinned ? "0" : "1"
        let signed = try await signedQuery([
            "talker_id": "\(talkerID)",
            "session_type": "1",
            "op_type": opType,
            "build": "0",
            "mobi_app": "web",
            "csrf_token": session.csrf,
            "csrf": session.csrf
        ])

        let _ = try await request(
            baseURL: vcBaseURL,
            path: "/session_svr/v1/session_svr/set_top",
            method: "POST",
            query: [:],
            body: signed,
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )
    }

    func removeConversation(session: BiliSession, talkerID: Int) async throws {
        let signed = try await signedQuery([
            "talker_id": "\(talkerID)",
            "session_type": "1",
            "build": "0",
            "mobi_app": "web",
            "csrf_token": session.csrf,
            "csrf": session.csrf
        ])

        let _ = try await request(
            baseURL: vcBaseURL,
            path: "/session_svr/v1/session_svr/remove_session",
            method: "POST",
            query: [:],
            body: signed,
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )
    }

    func fetchDanmaku(cid: Int) async throws -> [BiliDanmakuItem] {
        let url = URL(string: "https://comment.bilibili.com/\(cid).xml")!
        let data = try await rawDataRequest(url: url, headers: ["User-Agent": Self.webUserAgent])
        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        let pattern = #"<d p="([^"]+)">([\s\S]*?)</d>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: nsRange)

        return matches.compactMap { match in
            guard let paramRange = Range(match.range(at: 1), in: xml),
                  let textRange = Range(match.range(at: 2), in: xml) else {
                return nil
            }

            let params = xml[paramRange].split(separator: ",").map(String.init)
            let time = Double(params[safe: 0] ?? "") ?? 0
            let mode = Int(params[safe: 1] ?? "") ?? 1
            let color = Int(params[safe: 3] ?? "") ?? 0xFFFFFF
            let text = BiliFormat.decodeXMLEntities(String(xml[textRange]))

            guard !text.isEmpty else { return nil }

            return BiliDanmakuItem(
                id: "\(time)-\(text.hashValue)",
                time: time,
                text: text,
                mode: mode,
                colorValue: color
            )
        }
        .sorted { $0.time < $1.time }
    }

    func sendDanmaku(session: BiliSession, bvid: String, cid: Int, text: String, progressMS: Int) async throws {
        let payload = try await request(
            path: "/x/v2/dm/post",
            method: "POST",
            query: [:],
            body: [
                "type": "1",
                "oid": "\(cid)",
                "msg": text,
                "mode": "1",
                "bvid": bvid,
                "progress": "\(progressMS)",
                "color": "16777215",
                "fontsize": "25",
                "pool": "0",
                "rnd": "\(Int(Date().timeIntervalSince1970 * 1_000_000))",
                "csrf": session.csrf
            ],
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://www.bilibili.com/video/\(bvid)")
        )

        guard payload.code == 0 else {
            throw APIError.server(payload.message)
        }
    }

    func fetchUserProfile(mid: Int) async throws -> BiliUserProfile {
        async let profilePayload = request(
            path: "/x/space/wbi/acc/info",
            query: try await signedQuery([
                "mid": "\(mid)",
                "platform": "web",
                "web_location": "1550101"
            ]),
            headers: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)"
            ]
        )

        async let relationPayload = request(
            path: "/x/relation/stat",
            query: ["vmid": "\(mid)"]
        )

        async let archivePayload = request(
            path: "/x/space/navnum",
            query: ["mid": "\(mid)"]
        )

        let profile = try await profilePayload
        let relation = try await relationPayload
        let archive = try await archivePayload

        let sign = BiliFormat.plainText(profile.data.string("sign"))
        let followers = BiliFormat.countText(relation.data.raw["follower"])
        let following = BiliFormat.countText(relation.data.raw["following"])
        let archiveCount = BiliFormat.countText(archive.data.raw["video"])

        guard let name = profile.data.string("name") else {
            throw APIError.invalidResponse("UP 主信息为空")
        }

        return BiliUserProfile(
            mid: mid,
            name: BiliFormat.plainText(name),
            faceURL: BiliFormat.normalizeURL(profile.data.string("face")),
            sign: sign,
            followingText: following,
            followersText: followers,
            archiveCountText: archiveCount
        )
    }

    func fetchUserVideos(mid: Int, page: Int, pageSize: Int = 20) async throws -> [BiliVideo] {
        let payload = try await request(
            path: "/x/space/wbi/arc/search",
            query: try await signedQuery([
                "mid": "\(mid)",
                "pn": "\(page)",
                "ps": "\(pageSize)",
                "tid": "0",
                "order": "pubdate",
                "keyword": "",
                "platform": "web",
                "web_location": "1550101"
            ]),
            headers: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)"
            ]
        )

        let list = payload.data.dictionary("list")?.array("vlist") ?? []
        return list.compactMap(BiliVideo.init(json:))
    }

    func fetchVideoDetail(bvid: String) async throws -> BiliVideoDetail {
        try await fetchVideoDetail(query: ["bvid": bvid])
    }

    func fetchVideoDetail(aid: Int) async throws -> BiliVideoDetail {
        try await fetchVideoDetail(query: ["aid": "\(aid)"])
    }

    func fetchComments(oid: Int, type: Int = 1, nextOffset: String = "") async throws -> BiliCommentPage {
        let escapedOffset = nextOffset.replacingOccurrences(of: "\"", with: "\\\"")
        let payload = try await request(
            path: "/x/v2/reply/main",
            query: [
                "oid": "\(oid)",
                "type": "\(type)",
                "mode": "3",
                "pagination_str": "{\"offset\":\"\(escapedOffset)\"}"
            ]
        )

        let comments = payload.data.array("replies").compactMap(BiliComment.init(json:))
        let cursor = payload.data.dictionary("cursor")
        let paginationReply = cursor?.dictionary("pagination_reply")
        let isEnd = (cursor?["is_end"] as? Bool) ?? comments.isEmpty
        let next = paginationReply?.string("next_offset")
        return BiliCommentPage(comments: comments, nextOffset: next, isEnd: isEnd)
    }

    func fetchCommentReplies(oid: Int, rootCommentID: Int, type: Int = 1, page: Int) async throws -> [BiliComment] {
        let payload = try await request(
            path: "/x/v2/reply/reply",
            query: [
                "oid": "\(oid)",
                "root": "\(rootCommentID)",
                "pn": "\(page)",
                "type": "\(type)",
                "sort": "1"
            ]
        )

        return payload.data.array("replies").compactMap(BiliComment.init(json:))
    }

    func toggleDynamicLike(session: BiliSession, dynamicID: String, currentlyLiked: Bool) async throws {
        let _ = try await request(
            path: "/x/dynamic/feed/dyn/thumb",
            method: "POST",
            query: [
                "csrf": session.csrf
            ],
            body: [
                "dyn_id_str": dynamicID,
                "up": currentlyLiked ? "2" : "1",
                "spmid": "333.1365.0.0"
            ],
            contentType: .form,
            headers: authenticatedHeaders(session: session, referer: "https://t.bilibili.com/")
        )
    }

    func fetchPlayback(bvid: String, cid: Int) async throws -> BiliPlayback {
        let payload = try await request(
            path: "/x/player/wbi/playurl",
            query: try await signedQuery([
                "bvid": bvid,
                "cid": "\(cid)",
                "qn": "64",
                "fnval": "0",
                "fourk": "0"
            ]),
            headers: [
                "Referer": "https://www.bilibili.com/video/\(bvid)",
                "Origin": "https://www.bilibili.com"
            ]
        )

        if let durl = payload.data.array("durl").first,
           let url = BiliFormat.normalizeURL(durl.string("url")) {
            return BiliPlayback(streamURL: url, qualityDescription: "Progressive MP4")
        }

        if let dash = payload.data.dictionary("dash"),
           let video = dash.array("video").first,
           let url = BiliFormat.normalizeURL(video.string("baseUrl") ?? video.string("base_url")) {
            let quality = video.string("codecs") ?? "DASH"
            return BiliPlayback(streamURL: url, qualityDescription: quality)
        }

        throw APIError.invalidResponse("播放地址为空")
    }

    private func fetchVideoDetail(query: [String: String]) async throws -> BiliVideoDetail {
        let detail = try await fetchViewPayload(query: query)
        guard let video = BiliVideo(json: detail.data.raw) else {
            throw APIError.invalidResponse("视频详情解析失败")
        }

        let pages = detail.data.array("pages").compactMap(BiliVideoPage.init(json:))
        let relatedEnvelope = try? await request(
            path: "/x/web-interface/archive/related",
            query: query
        )
        let related = relatedEnvelope?.dataList.compactMap(BiliVideo.init(json:)) ?? []
        return BiliVideoDetail(video: video, pages: pages, related: related)
    }

    private func fetchViewPayload(query: [String: String]) async throws -> APIEnvelope {
        try await request(
            path: "/x/web-interface/view",
            query: query,
            headers: ["Referer": "https://www.bilibili.com"]
        )
    }

    private func fetchPrivateUserCards(session: BiliSession, uids: [Int]) async throws -> [Int: BiliUserCard] {
        guard !uids.isEmpty else { return [:] }
        let payload = try await request(
            baseURL: vcBaseURL,
            path: "/account/v1/user/cards",
            query: [
                "uids": uids.map(String.init).joined(separator: ","),
                "build": "0",
                "mobi_app": "web"
            ],
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )

        let cards: [[String: Any]]
        if let direct = payload.data.raw["data"] as? [[String: Any]] {
            cards = direct
        } else {
            cards = payload.data.array("data")
        }

        var result: [Int: BiliUserCard] = [:]
        for card in cards {
            guard let mid = BiliFormat.intValue(card["mid"] ?? card["uid"]) else { continue }
            result[mid] = BiliUserCard(
                mid: mid,
                name: BiliFormat.plainText(card.string("name") ?? card.string("uname") ?? "用户 \(mid)"),
                faceURL: BiliFormat.normalizeURL(card.string("face") ?? card.string("face_url"))
            )
        }
        return result
    }

    private func acknowledgeConversation(session: BiliSession, talkerID: Int, ackSeqNo: Int) async throws {
        let _ = try await request(
            baseURL: vcBaseURL,
            path: "/session_svr/v1/session_svr/update_ack",
            query: try await signedQuery([
                "talker_id": "\(talkerID)",
                "session_type": "1",
                "ack_seqno": "\(ackSeqNo)",
                "build": "0",
                "mobi_app": "web",
                "csrf_token": session.csrf,
                "csrf": session.csrf
            ]),
            headers: authenticatedHeaders(session: session, referer: "https://message.bilibili.com/")
        )
    }

    private var tvHeaders: [String: String] {
        [
            "buvid": AppPreferences.anonymousBuvid3,
            "env": "prod",
            "app-key": "android_hd",
            "User-Agent": Self.appUserAgent,
            "x-bili-trace-id": appTraceID,
            "x-bili-aurora-eid": "",
            "x-bili-aurora-zone": "",
            "bili-http-engine": "cronet",
            "content-type": "application/x-www-form-urlencoded; charset=utf-8"
        ]
    }

    private var loginHeaders: [String: String] {
        [
            "buvid": AppPreferences.anonymousBuvid3,
            "env": "prod",
            "app-key": "android_hd",
            "User-Agent": Self.appUserAgent,
            "x-bili-trace-id": appTraceID,
            "x-bili-aurora-eid": "",
            "x-bili-aurora-zone": "",
            "bili-http-engine": "cronet",
            "content-type": "application/x-www-form-urlencoded; charset=utf-8"
        ]
    }

    private var anonymousCookieHeader: String {
        let buvid3 = AppPreferences.anonymousBuvid3
        let bNut = "\(Int(Date().timeIntervalSince1970))"
        return "buvid3=\(buvid3); b_nut=\(bNut); _uuid=\(UUID().uuidString)"
    }

    private var anonymousAppHeaders: [String: String] {
        [
            "User-Agent": Self.appUserAgent,
            "Cookie": anonymousCookieHeader,
            "buvid": AppPreferences.anonymousBuvid3,
            "fp_local": AppPreferences.appFingerprint,
            "fp_remote": AppPreferences.appFingerprint,
            "session_id": "11111111",
            "env": "prod",
            "app-key": "android_hd",
            "x-bili-trace-id": appTraceID,
            "x-bili-aurora-eid": "",
            "x-bili-aurora-zone": "",
            "bili-http-engine": "cronet"
        ]
    }

    private func authenticatedHeaders(session: BiliSession, referer: String = "https://www.bilibili.com") -> [String: String] {
        [
            "User-Agent": Self.webUserAgent,
            "Cookie": session.cookieHeader,
            "Referer": referer,
            "Origin": "https://www.bilibili.com"
        ]
    }

    private func request(
        path: String,
        method: String = "GET",
        query: [String: String],
        body: [String: Any]? = nil,
        contentType: RequestContentType = .json,
        headers: [String: String] = [:]
    ) async throws -> APIEnvelope {
        try await request(
            baseURL: apiBaseURL,
            path: path,
            method: method,
            query: query,
            body: body,
            contentType: contentType,
            headers: headers,
            session: headers["Cookie"] == nil ? anonymousSession : authenticatedSession
        )
    }

    private func request(
        baseURL: URL,
        path: String,
        method: String = "GET",
        query: [String: String],
        body: [String: Any]? = nil,
        contentType: RequestContentType = .json,
        headers: [String: String] = [:],
        session: URLSession? = nil
    ) async throws -> APIEnvelope {
        let envelope = try await rawRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            query: query,
            body: body,
            contentType: contentType,
            headers: headers,
            session: session ?? (headers["Cookie"] == nil ? anonymousSession : authenticatedSession)
        )

        guard envelope.code == 0 else {
            throw APIError.server(envelope.message.isEmpty ? "接口返回失败" : envelope.message)
        }
        return envelope
    }

    private func rawRequest(
        baseURL: URL,
        path: String,
        method: String = "GET",
        query: [String: String],
        body: [String: Any]? = nil,
        contentType: RequestContentType = .json,
        headers: [String: String] = [:],
        session: URLSession
    ) async throws -> APIEnvelope {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(Self.webUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body {
            switch contentType {
            case .json:
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            case .form:
                request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = formEncoded(body).data(using: .utf8)
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http("接口请求失败")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw APIError.invalidResponse("接口未返回 JSON 对象")
        }

        return APIEnvelope(json: json)
    }

    private func rawDataRequest(url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await anonymousSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http("原始数据请求失败")
        }
        return data
    }

    private func signedQuery(_ query: [String: String]) async throws -> [String: String] {
        var result = query
        result["wts"] = "\(Int(Date().timeIntervalSince1970))"
        let mixinKey = try await currentMixinKey()
        let sortedQuery = result.keys.sorted().map { key in
            let sanitized = (result[key] ?? "").replacingOccurrences(of: "[!'()*]", with: "", options: .regularExpression)
            return "\(Self.percentEncode(key))=\(Self.percentEncode(sanitized))"
        }.joined(separator: "&")
        result["w_rid"] = Self.md5("\(sortedQuery)\(mixinKey)")
        return result
    }

    private func appSignedParameters(_ query: [String: String]) -> [String: String] {
        var result = query
        result["appkey"] = appKey
        result["ts"] = "\(Int(Date().timeIntervalSince1970))"
        let queryString = result.keys.sorted().map { key in
            "\(Self.percentEncode(key))=\(Self.percentEncode(result[key] ?? ""))"
        }.joined(separator: "&")
        result["sign"] = Self.md5(queryString + appSecret)
        return result
    }

    private func fetchLoginPublicKey() async throws -> String {
        let payload = try await request(
            baseURL: passBaseURL,
            path: "/x/passport-login/web/key",
            query: [
                "disable_rcmd": "0",
                "local_id": AppPreferences.anonymousBuvid3
            ]
        )

        guard let key = payload.data.string("key"), !key.isEmpty else {
            throw APIError.invalidResponse("缺少短信登录公钥")
        }
        return key
    }

    private func encryptRandomToken(usingPEM pem: String) throws -> String {
        let publicKeyData = try publicKeyData(fromPEM: pem)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 1024
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(publicKeyData as CFData, attributes as CFDictionary, &error) else {
            throw APIError.invalidResponse((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "创建短信登录公钥失败")
        }

        let random = Self.randomString(length: 16)
        guard let encryptedData = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, Data(random.utf8) as CFData, &error) else {
            throw APIError.invalidResponse((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "短信登录随机串加密失败")
        }

        let encrypted = encryptedData as Data
        return encrypted.base64EncodedString()
    }

    private func publicKeyData(fromPEM pem: String) throws -> Data {
        let content = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let data = Data(base64Encoded: content) else {
            throw APIError.invalidResponse("短信登录公钥格式无效")
        }
        return data
    }

    private func sanitizedCountryCode(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? "86" : digits
    }

    private func sanitizedPhone(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    private func currentMixinKey() async throws -> String {
        let today = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if cachedMixinDay == today, let cachedMixinKey {
            return cachedMixinKey
        }

        let payload = try await rawRequest(
            baseURL: apiBaseURL,
            path: "/x/web-interface/nav",
            query: [:],
            headers: [:],
            session: anonymousSession
        )
        guard let wbiImage = payload.data.dictionary("wbi_img") else {
            throw APIError.invalidResponse("缺少 WBI 图片信息")
        }

        let imgName = Self.fileStem(from: wbiImage.string("img_url"))
        let subName = Self.fileStem(from: wbiImage.string("sub_url"))
        let source = imgName + subName
        let table = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13]
        let characters = Array(source)
        let key = String(table.compactMap { index in
            guard index < characters.count else { return nil }
            return characters[index]
        })

        cachedMixinDay = today
        cachedMixinKey = key
        return key
    }

    private func formEncoded(_ body: [String: Any]) -> String {
        body.map { key, value in
            let stringValue: String
            switch value {
            case let value as String:
                stringValue = value
            case let value as NSNumber:
                stringValue = value.stringValue
            default:
                if let data = try? JSONSerialization.data(withJSONObject: value),
                   let json = String(data: data, encoding: .utf8) {
                    stringValue = json
                } else {
                    stringValue = "\(value)"
                }
            }
            return "\(Self.percentEncode(key))=\(Self.percentEncode(stringValue))"
        }
        .sorted()
        .joined(separator: "&")
    }

    private func compactQuery(_ query: [String: String?]) -> [String: String] {
        query.compactMapValues { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }

    private static func fileStem(from urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString) else { return "" }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private static func randomString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }

    private static func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

private enum RequestContentType {
    case json
    case form
}

private struct APIEnvelope {
    let code: Int
    let message: String
    let data: JSONBox
    let dataList: [[String: Any]]

    init(json: [String: Any]) {
        self.code = BiliFormat.intValue(json["code"]) ?? -1
        self.message = (json["message"] as? String) ?? (json["msg"] as? String) ?? ""
        if let data = json["data"] as? [String: Any] {
            self.data = JSONBox(raw: data)
        } else if let result = json["result"] as? [String: Any] {
            self.data = JSONBox(raw: result)
        } else {
            self.data = JSONBox(raw: [:])
        }

        if let data = json["data"] as? [[String: Any]] {
            self.dataList = data
        } else if let result = json["result"] as? [[String: Any]] {
            self.dataList = result
        } else {
            self.dataList = []
        }
    }
}

private struct JSONBox {
    let raw: [String: Any]

    func string(_ key: String) -> String? {
        raw.string(key)
    }

    func dictionary(_ key: String) -> [String: Any]? {
        raw[key] as? [String: Any]
    }

    func array(_ key: String) -> [[String: Any]] {
        raw[key] as? [[String: Any]] ?? []
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse(String)
    case http(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "请求地址无效"
        case let .invalidResponse(message),
             let .http(message),
             let .server(message):
            return message
        }
    }
}
