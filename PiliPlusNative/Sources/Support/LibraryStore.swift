import Combine
import Foundation

struct WatchRecord: Identifiable, Hashable, Codable {
    let video: BiliVideo
    let pageCID: Int
    let pageIndex: Int
    let pageTitle: String
    let pageDuration: Int
    let progressSeconds: Double
    let updatedAt: TimeInterval

    var id: String { video.id }

    var pageLabel: String {
        if pageTitle.isEmpty {
            return "P\(pageIndex)"
        }
        return "P\(pageIndex) \(pageTitle)"
    }

    var progressRatio: Double {
        guard pageDuration > 0 else { return 0 }
        return min(max(progressSeconds / Double(pageDuration), 0), 1)
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [BiliVideo]
    @Published private(set) var history: [WatchRecord]

    private let favoritesKey = "library_favorites_v1"
    private let historyKey = "library_history_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        self.favorites = []
        self.history = []
        load()
    }

    func isFavorite(_ video: BiliVideo) -> Bool {
        favorites.contains(where: { $0.id == video.id })
    }

    func isFavorite(bvid: String) -> Bool {
        favorites.contains(where: { $0.bvid == bvid })
    }

    func toggleFavorite(_ video: BiliVideo) {
        if let index = favorites.firstIndex(where: { $0.id == video.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        persistFavorites()
    }

    func removeFavorite(bvid: String) {
        favorites.removeAll(where: { $0.bvid == bvid })
        persistFavorites()
    }

    func removeFavorite(video: BiliVideo) {
        favorites.removeAll(where: { $0.id == video.id })
        persistFavorites()
    }

    func clearFavorites() {
        favorites.removeAll()
        persistFavorites()
    }

    func historyRecord(for bvid: String) -> WatchRecord? {
        history.first(where: { $0.video.bvid == bvid })
    }

    func historyRecord(video: BiliVideo) -> WatchRecord? {
        history.first(where: { $0.video.id == video.id })
    }

    func resumeProgress(for bvid: String, cid: Int) -> Double? {
        guard let record = historyRecord(for: bvid), record.pageCID == cid else {
            return nil
        }
        return record.progressSeconds
    }

    func updateWatchRecord(video: BiliVideo, page: BiliVideoPage, progressSeconds: Double) {
        let clamped = max(0, min(progressSeconds, Double(max(page.duration, 0))))
        let record = WatchRecord(
            video: video,
            pageCID: page.cid,
            pageIndex: page.page,
            pageTitle: page.title,
            pageDuration: page.duration,
            progressSeconds: clamped,
            updatedAt: Date().timeIntervalSince1970
        )

        history.removeAll(where: { $0.video.id == video.id })
        history.insert(record, at: 0)
        history = Array(history.prefix(100))
        persistHistory()
    }

    func removeHistory(bvid: String) {
        history.removeAll(where: { $0.video.bvid == bvid })
        persistHistory()
    }

    func removeHistory(video: BiliVideo) {
        history.removeAll(where: { $0.video.id == video.id })
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    func refreshSnapshots(with video: BiliVideo) {
        if let favoriteIndex = favorites.firstIndex(where: { $0.id == video.id }) {
            favorites[favoriteIndex] = video
            persistFavorites()
        }

        if let historyIndex = history.firstIndex(where: { $0.video.id == video.id }) {
            let record = history[historyIndex]
            history[historyIndex] = WatchRecord(
                video: video,
                pageCID: record.pageCID,
                pageIndex: record.pageIndex,
                pageTitle: record.pageTitle,
                pageDuration: record.pageDuration,
                progressSeconds: record.progressSeconds,
                updatedAt: record.updatedAt
            )
            persistHistory()
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? decoder.decode([BiliVideo].self, from: data) {
            favorites = decoded
        }

        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? decoder.decode([WatchRecord].self, from: data) {
            history = decoded
        }
    }

    private func persistFavorites() {
        guard let data = try? encoder.encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: favoritesKey)
    }

    private func persistHistory() {
        guard let data = try? encoder.encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
