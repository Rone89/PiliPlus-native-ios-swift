import Foundation
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.957, green: 0.373, blue: 0.435)
    static let card = Color(uiColor: .secondarySystemBackground)
}

enum AppPreferences {
    private static let defaults = UserDefaults.standard
    private static let playbackRateKey = "preference_playback_rate"
    private static let autoPlayNextKey = "preference_auto_play_next"
    private static let showDanmakuKey = "preference_show_danmaku"
    private static let recommendWithAccountKey = "preference_recommend_with_account"
    private static let messageDeviceIDKey = "preference_message_device_id"
    private static let anonymousBuvid3Key = "preference_anonymous_buvid3"
    private static let loginDeviceIDKey = "preference_login_device_id"
    private static let appFingerprintKey = "preference_app_fingerprint"

    static var playbackRate: Double {
        get {
            let value = defaults.double(forKey: playbackRateKey)
            return value == 0 ? 1.0 : value
        }
        set {
            defaults.set(newValue, forKey: playbackRateKey)
        }
    }

    static var autoPlayNext: Bool {
        get {
            if defaults.object(forKey: autoPlayNextKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoPlayNextKey)
        }
        set {
            defaults.set(newValue, forKey: autoPlayNextKey)
        }
    }

    static var showDanmaku: Bool {
        get {
            if defaults.object(forKey: showDanmakuKey) == nil {
                return true
            }
            return defaults.bool(forKey: showDanmakuKey)
        }
        set {
            defaults.set(newValue, forKey: showDanmakuKey)
        }
    }

    static var recommendWithAccount: Bool {
        get {
            if defaults.object(forKey: recommendWithAccountKey) == nil {
                return true
            }
            return defaults.bool(forKey: recommendWithAccountKey)
        }
        set {
            defaults.set(newValue, forKey: recommendWithAccountKey)
        }
    }

    static var messageDeviceID: String {
        get {
            if let existing = defaults.string(forKey: messageDeviceIDKey), !existing.isEmpty {
                return existing
            }
            let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(generated, forKey: messageDeviceIDKey)
            return generated
        }
        set {
            defaults.set(newValue, forKey: messageDeviceIDKey)
        }
    }

    static var anonymousBuvid3: String {
        get {
            if let existing = defaults.string(forKey: anonymousBuvid3Key), !existing.isEmpty {
                return existing
            }
            let generated = "XY\(UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased())infoc"
            defaults.set(generated, forKey: anonymousBuvid3Key)
            return generated
        }
        set {
            defaults.set(newValue, forKey: anonymousBuvid3Key)
        }
    }

    static var loginDeviceID: String {
        get {
            if let existing = defaults.string(forKey: loginDeviceIDKey), !existing.isEmpty {
                return existing
            }
            let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(generated, forKey: loginDeviceIDKey)
            return generated
        }
        set {
            defaults.set(newValue, forKey: loginDeviceIDKey)
        }
    }

    static var appFingerprint: String {
        get {
            if let existing = defaults.string(forKey: appFingerprintKey), !existing.isEmpty {
                return existing
            }
            let generated = String(repeating: "1", count: 64)
            defaults.set(generated, forKey: appFingerprintKey)
            return generated
        }
        set {
            defaults.set(newValue, forKey: appFingerprintKey)
        }
    }
}

enum FeedKind: String, CaseIterable, Identifiable {
    case recommend

    var id: String { rawValue }

    var title: String {
        "推荐"
    }

    var subtitle: String {
        "根据当前模式加载首页推荐流"
    }
}

enum BiliFormat {
    static func countText(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = plainText(string)
            guard !trimmed.isEmpty else { return nil }
            if trimmed.range(of: #"^\d+$"#, options: .regularExpression) == nil {
                return trimmed
            }
            if let intValue = Int(trimmed) {
                return countText(intValue)
            }
            return trimmed
        }

        if let intValue = intValue(value) {
            switch intValue {
            case 100_000_000...:
                return String(format: "%.1f亿", Double(intValue) / 100_000_000).replacingOccurrences(of: ".0", with: "")
            case 10_000...:
                return String(format: "%.1f万", Double(intValue) / 10_000).replacingOccurrences(of: ".0", with: "")
            default:
                return "\(intValue)"
            }
        }

        return nil
    }

    static func durationText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "--:--" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remaining = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%02d:%02d", minutes, remaining)
    }

    static func progressText(_ seconds: Double, total: Int?) -> String {
        guard seconds.isFinite else { return "未开始" }
        let current = max(0, Int(seconds.rounded()))
        if let total, total > 0 {
            let ratio = min(max(seconds / Double(total), 0), 1)
            return "\(durationText(current)) / \(durationText(total)) · \(Int(ratio * 100))%"
        }
        return durationText(current)
    }

    static func parseDuration(_ value: Any?) -> Int {
        if let intValue = intValue(value) {
            return intValue
        }

        guard let text = value as? String else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return 0 }
        if parts.count == 3 {
            return (parts[0] * 3600) + (parts[1] * 60) + parts[2]
        }
        if parts.count == 2 {
            return (parts[0] * 60) + parts[1]
        }
        return parts[0]
    }

    static func plainText(_ value: String?) -> String {
        guard let value else { return "" }
        var text = value
        let replacements: [(String, String)] = [
            ("<em class=\"keyword\">", ""),
            ("</em>", ""),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("<br/>", "\n"),
            ("<br />", "\n")
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeXMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    static func relativeDate(_ timestamp: Int?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func absoluteDate(_ timestamp: TimeInterval?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func normalizeURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        if value.hasPrefix("http://") {
            return URL(string: "https://" + value.dropFirst("http://".count))
        }
        return URL(string: value)
    }

    static func color(from decimal: Int?) -> Color {
        let value = decimal ?? 0xFFFFFF
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

struct SearchHistoryStore {
    private static let key = "search_history"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func save(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = load().filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(items.prefix(12)), forKey: key)
    }

    static func remove(_ keyword: String) {
        let items = load().filter { $0 != keyword }
        UserDefaults.standard.set(items, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum BiliInputParser {
    static func extractBVID(from input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"BV[0-9A-Za-z]{10}"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              let matchRange = Range(match.range, in: input) else {
            return nil
        }
        return String(input[matchRange]).uppercased()
    }

    static func extractAID(from input: String) -> Int? {
        let trimmed = input.trimmed
        if let numeric = Int(trimmed), numeric > 0 {
            return numeric
        }

        let patterns = [
            #"(?i)\bav(\d+)\b"#,
            #"(?i)[?&]aid=(\d+)"#,
            #"(?i)[?&]avid=(\d+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            guard let match = regex.firstMatch(in: input, options: [], range: range),
                  match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: input) else {
                continue
            }
            return Int(input[matchRange])
        }

        return nil
    }
}

struct VideoRoute: Identifiable, Hashable {
    let bvid: String?
    let aid: Int?

    var id: String { bvid ?? aid.map { "av\($0)" } ?? UUID().uuidString }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
