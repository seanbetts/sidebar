import Foundation

public protocol AuthStateStore {
    func saveAccessToken(_ token: String?)
    func saveUserId(_ userId: String?)
    func loadAccessToken() -> String?
    func loadUserId() -> String?
    func clear()
}

public final class InMemoryAuthStateStore: AuthStateStore {
    private var accessToken: String?
    private var userId: String?

    public init() {
    }

    public func saveAccessToken(_ token: String?) {
        accessToken = token
    }

    public func saveUserId(_ userId: String?) {
        self.userId = userId
    }

    public func loadAccessToken() -> String? {
        accessToken
    }

    public func loadUserId() -> String? {
        userId
    }

    public func clear() {
        accessToken = nil
        userId = nil
    }
}

public final class SupabaseAuthAdapter: AuthSession {
    public private(set) var accessToken: String?
    public private(set) var userId: String?

    private let stateStore: AuthStateStore

    public init(stateStore: AuthStateStore) {
        self.stateStore = stateStore
        self.accessToken = stateStore.loadAccessToken()
        self.userId = stateStore.loadUserId()
    }

    public func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    public func signOut() async {
        accessToken = nil
        userId = nil
        stateStore.clear()
    }

    public func restoreSession(accessToken: String?, userId: String?) {
        self.accessToken = accessToken
        self.userId = userId
        stateStore.saveAccessToken(accessToken)
        stateStore.saveUserId(userId)
    }
}
