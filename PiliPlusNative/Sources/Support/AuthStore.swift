import Combine
import Foundation

@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var session: BiliSession?
    @Published private(set) var currentUser: BiliCurrentUser?
    @Published private(set) var unreadState: BiliUnreadState
    @Published private(set) var isSyncing = false

    private let sessionKey = "auth_session_v1"
    private let userKey = "auth_user_v1"
    private let unreadKey = "auth_unread_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        self.unreadState = .empty
        load()
    }

    var isLoggedIn: Bool {
        session?.isLoggedIn == true
    }

    func completeLogin(session: BiliSession) async {
        self.session = session
        persistSession()
        await sync()
    }

    func syncIfNeeded() async {
        guard isLoggedIn, currentUser == nil else { return }
        await sync()
    }

    func sync() async {
        guard let session, session.isLoggedIn else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            async let user = BiliAPIClient.shared.fetchCurrentUser(session: session)
            async let unread = BiliAPIClient.shared.fetchUnreadState(session: session)
            currentUser = try await user
            unreadState = try await unread
            persistUser()
            persistUnreadState()
        } catch {
            // Keep cached user info if sync fails.
        }
    }

    func logout() async {
        let currentSession = session
        session = nil
        currentUser = nil
        unreadState = .empty
        persistSession()
        persistUser()
        persistUnreadState()

        if let currentSession {
            try? await BiliAPIClient.shared.logout(session: currentSession)
        }
    }

    private func load() {
        if let sessionData = UserDefaults.standard.data(forKey: sessionKey),
           let decodedSession = try? decoder.decode(BiliSession.self, from: sessionData) {
            session = decodedSession
        }

        if let userData = UserDefaults.standard.data(forKey: userKey),
           let decodedUser = try? decoder.decode(BiliCurrentUser.self, from: userData) {
            currentUser = decodedUser
        }

        if let unreadData = UserDefaults.standard.data(forKey: unreadKey),
           let decodedUnread = try? decoder.decode(BiliUnreadState.self, from: unreadData) {
            unreadState = decodedUnread
        }
    }

    private func persistSession() {
        guard let session else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        guard let data = try? encoder.encode(session) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    private func persistUser() {
        guard let currentUser else {
            UserDefaults.standard.removeObject(forKey: userKey)
            return
        }
        guard let data = try? encoder.encode(currentUser) else { return }
        UserDefaults.standard.set(data, forKey: userKey)
    }

    private func persistUnreadState() {
        guard let data = try? encoder.encode(unreadState) else { return }
        UserDefaults.standard.set(data, forKey: unreadKey)
    }
}
