import CryptoKit
import Foundation

actor BiliAPIClient {
    static let shared = BiliAPIClient()

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private let apiBaseURL = URL(string: "https://api.bilibili.com")!
    private var cachedMixinKey: String?
    private var cachedMixinDay: Int?

    func fetchRecommended(page: Int, pageSize: Int = 20) async throws -> [BiliVideo] {
        let index = max(page - 1, 0)
        let payload = try await request(
            path: "/x/web-interface/wbi/index/top/feed/rcmd",
            query: try await signedQuery([
                "version": "1",
                "feed_version": "V8",
                "homepage_ver": "1",
                "ps": "\(pageSize)",
                "fresh_idx": "\(index)",
                "brush": "\(index)",
                "fresh_type": "4"
            ])
        )

        let items = payload.data.array("item")
        return items.compactMap { item in
            guard item.string("goto") == "av" else { return nil }
            return BiliVideo(json: item)
        }
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
                "Referer": "https://search.bilibili.com/video?keyword=\(keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword)"
            ]
        )

        return payload.data.array("result").compactMap(BiliVideo.init(json:))
    }

    func fetchVideoDetail(bvid: String) async throws -> BiliVideoDetail {
        async let detailPayload = request(
            path: "/x/web-interface/view",
            query: ["bvid": bvid]
        )

        async let relatedPayload = request(
            path: "/x/web-interface/archive/related",
            query: ["bvid": bvid]
        )

        let detail = try await detailPayload
        guard let video = BiliVideo(json: detail.data.raw) else {
            throw APIError.invalidResponse("视频详情解析失败")
        }

        let relatedEnvelope = try await relatedPayload
        let pages = detail.data.array("pages").compactMap(BiliVideoPage.init(json:))
        let related = relatedEnvelope.dataList.compactMap(BiliVideo.init(json:))
        return BiliVideoDetail(video: video, pages: pages, related: related)
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

    private func request(
        path: String,
        query: [String: String],
        headers: [String: String] = [:]
    ) async throws -> APIEnvelope {
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.http("接口请求失败")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw APIError.invalidResponse("接口未返回 JSON 对象")
        }

        let envelope = APIEnvelope(json: json)
        guard envelope.code == 0 else {
            throw APIError.server(envelope.message.isEmpty ? "接口返回失败" : envelope.message)
        }

        return envelope
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

    private func currentMixinKey() async throws -> String {
        let today = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if cachedMixinDay == today, let cachedMixinKey {
            return cachedMixinKey
        }

        let payload = try await request(path: "/x/web-interface/nav", query: [:])
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

    private static func fileStem(from urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString) else { return "" }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private static func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
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
