import Combine
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var savedSessions: [BiliSession]
    @Published private(set) var currentSessionMID: Int?
    @Published private(set) var currentUser: BiliCurrentUser?
    @Published private(set) var unreadState: BiliUnreadState
    @Published private(set) var isSyncing = false

    private let sessionsKey = "auth_sessions_v2"
    private let currentMIDKey = "auth_current_mid_v2"
    private let userCacheKey = "auth_user_cache_v2"
    private let unreadCacheKey = "auth_unread_cache_v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var userCache: [String: BiliCurrentUser]
    private var unreadCache: [String: BiliUnreadState]

    private init() {
        self.savedSessions = []
        self.unreadState = .empty
        self.userCache = [:]
        self.unreadCache = [:]
        load()
    }

    var session: BiliSession? {
        if let currentSessionMID {
            return savedSessions.first(where: { $0.mid == currentSessionMID })
        }
        return savedSessions.first
    }

    var isLoggedIn: Bool {
        session?.isLoggedIn == true
    }

    func completeLogin(session newSession: BiliSession) async {
        guard let mid = newSession.mid else { return }

        if let index = savedSessions.firstIndex(where: { $0.mid == mid }) {
            savedSessions[index] = newSession
        } else {
            savedSessions.insert(newSession, at: 0)
        }

        currentSessionMID = mid
        persistSessions()
        persistCurrentMID()
        await sync()
    }

    func syncIfNeeded() async {
        guard isLoggedIn else { return }
        guard currentUser == nil else { return }
        await sync()
    }

    func sync() async {
        guard let session, session.isLoggedIn else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            async let user = BiliAPIClient.shared.fetchCurrentUser(session: session)
            async let unread = BiliAPIClient.shared.fetchUnreadState(session: session)
            let currentUser = try await user
            let unreadState = try await unread
            self.currentUser = currentUser
            self.unreadState = unreadState
            userCache["\(currentUser.mid)"] = currentUser
            unreadCache["\(currentUser.mid)"] = unreadState
            persistUserCache()
            persistUnreadCache()
        } catch {
            // Keep cached data if refresh fails.
        }
    }

    func switchTo(mid: Int) async {
        guard savedSessions.contains(where: { $0.mid == mid }) else { return }
        currentSessionMID = mid
        currentUser = userCache["\(mid)"]
        unreadState = unreadCache["\(mid)"] ?? .empty
        persistCurrentMID()
        await sync()
    }

    func removeAccount(mid: Int) async {
        savedSessions.removeAll(where: { $0.mid == mid })
        userCache.removeValue(forKey: "\(mid)")
        unreadCache.removeValue(forKey: "\(mid)")

        if currentSessionMID == mid {
            currentSessionMID = savedSessions.first?.mid
            if let currentSessionMID {
                currentUser = userCache["\(currentSessionMID)"]
                unreadState = unreadCache["\(currentSessionMID)"] ?? .empty
                await sync()
            } else {
                currentUser = nil
                unreadState = .empty
            }
        }

        persistSessions()
        persistCurrentMID()
        persistUserCache()
        persistUnreadCache()
    }

    func logout() async {
        guard let currentSession = session else { return }
        let mid = currentSession.mid
        try? await BiliAPIClient.shared.logout(session: currentSession)
        if let mid {
            await removeAccount(mid: mid)
        }
    }

    func displayName(for session: BiliSession) -> String {
        if let mid = session.mid, let cachedUser = userCache["\(mid)"] {
            return cachedUser.name
        }
        if let mid = session.mid {
            return "UID \(mid)"
        }
        return "未命名账号"
    }

    private func load() {
        if let sessionData = UserDefaults.standard.data(forKey: sessionsKey),
           let decodedSessions = try? decoder.decode([BiliSession].self, from: sessionData) {
            savedSessions = decodedSessions
        }

        currentSessionMID = UserDefaults.standard.object(forKey: currentMIDKey) as? Int

        if let userData = UserDefaults.standard.data(forKey: userCacheKey),
           let decodedCache = try? decoder.decode([String: BiliCurrentUser].self, from: userData) {
            userCache = decodedCache
        }

        if let unreadData = UserDefaults.standard.data(forKey: unreadCacheKey),
           let decodedUnread = try? decoder.decode([String: BiliUnreadState].self, from: unreadData) {
            unreadCache = decodedUnread
        }

        if currentSessionMID == nil {
            currentSessionMID = savedSessions.first?.mid
        }

        if let currentSessionMID {
            currentUser = userCache["\(currentSessionMID)"]
            unreadState = unreadCache["\(currentSessionMID)"] ?? .empty
        } else {
            currentUser = nil
            unreadState = .empty
        }
    }

    private func persistSessions() {
        guard let data = try? encoder.encode(savedSessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
    }

    private func persistCurrentMID() {
        if let currentSessionMID {
            UserDefaults.standard.set(currentSessionMID, forKey: currentMIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentMIDKey)
        }
    }

    private func persistUserCache() {
        guard let data = try? encoder.encode(userCache) else { return }
        UserDefaults.standard.set(data, forKey: userCacheKey)
    }

    private func persistUnreadCache() {
        guard let data = try? encoder.encode(unreadCache) else { return }
        UserDefaults.standard.set(data, forKey: unreadCacheKey)
    }
}
