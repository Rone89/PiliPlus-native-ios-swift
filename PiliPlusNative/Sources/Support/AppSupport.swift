import Foundation
import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.957, green: 0.373, blue: 0.435)
    static let card = Color(uiColor: .secondarySystemBackground)
}

enum FeedKind: String {
    case recommend
    case popular

    var title: String {
        switch self {
        case .recommend:
            return "推荐"
        case .popular:
            return "热门"
        }
    }

    var subtitle: String {
        switch self {
        case .recommend:
            return "基于 Bilibili 推荐接口的原生 Swift 视频流"
        case .popular:
            return "全站热门视频榜单"
        }
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

    static func relativeDate(_ timestamp: Int?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func normalizeURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        return URL(string: value)
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
            let digits = value.filter(\.isNumber)
            return Int(digits)
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
