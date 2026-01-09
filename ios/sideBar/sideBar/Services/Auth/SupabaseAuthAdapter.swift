import Foundation
import Supabase
import Combine

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

@MainActor
public final class SupabaseAuthAdapter: ObservableObject, AuthSession {
    @Published public private(set) var accessToken: String?
    @Published public private(set) var userId: String?

    private let stateStore: AuthStateStore
    private let supabase: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    public init(config: EnvironmentConfig, stateStore: AuthStateStore) {
        self.stateStore = stateStore

        supabase = SupabaseClient(
            supabaseURL: config.supabaseUrl,
            supabaseKey: config.supabaseAnonKey
        )

        if let session = supabase.auth.currentSession {
            restoreSession(accessToken: session.accessToken, userId: session.user.id.uuidString)
        } else {
            self.accessToken = stateStore.loadAccessToken()
            self.userId = stateStore.loadUserId()
        }

        authStateTask = Task { [supabase, weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                self.applySession(session)
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    public func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
        if let session = supabase.auth.currentSession {
            restoreSession(accessToken: session.accessToken, userId: session.user.id.uuidString)
        }
    }

    public func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            // Best effort: clear local auth even if server sign-out fails.
        }
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

    private func applySession(_ session: Session?) {
        if let session {
            restoreSession(accessToken: session.accessToken, userId: session.user.id.uuidString)
        } else {
            restoreSession(accessToken: nil, userId: nil)
        }
    }
}
