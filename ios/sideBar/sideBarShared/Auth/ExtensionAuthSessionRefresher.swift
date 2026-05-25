import Foundation
import Supabase

/// Refreshes Supabase auth sessions for app extensions using shared keychain state.
public final class ExtensionAuthSessionRefresher {
    private let keychain: KeychainAuthStateStore
    private let supabase: SupabaseClient
    private let refreshLeadTime: TimeInterval = 300

    /// Creates a refresher from extension configuration stored in the bundle.
    public init?(keychain: KeychainAuthStateStore, bundle: Bundle = .main) {
        guard let config = Self.loadConfig(from: bundle) else {
            return nil
        }
        self.keychain = keychain
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: SupabaseKeychainStorageBridge(stateStore: keychain),
            emitLocalSessionAsInitialSession: true
        )
        self.supabase = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
    }

    /// Ensures the stored access token is present and refreshed when near expiry.
    public func ensureValidSession(forceRefresh: Bool = false) async -> Bool {
        let accessToken: String
        do {
            guard let token = try keychain.loadAccessToken(), !token.isEmpty else {
                return false
            }
            accessToken = token
        } catch {
            return false
        }

        if forceRefresh || Self.shouldRefreshAccessToken(accessToken, leadTime: refreshLeadTime) {
            do {
                let session = try await supabase.auth.refreshSession()
                try keychain.saveAccessToken(session.accessToken)
                try keychain.saveUserId(session.user.id.uuidString)
                return true
            } catch {
                return false
            }
        }

        return true
    }

    /// Returns whether a JWT should be refreshed before use.
    public static func shouldRefreshAccessToken(
        _ accessToken: String,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        JWTExpiry.shouldRefreshAccessToken(accessToken, now: now, leadTime: leadTime)
    }

    private static func loadConfig(from bundle: Bundle) -> ExtensionSupabaseConfig? {
        guard
            let supabaseURLValue = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let normalizedURL = ConfigNormalization.normalizeConfigValue(supabaseURLValue),
            let supabaseURL = ConfigNormalization.parseHTTPURL(from: normalizedURL),
            let supabaseAnonKeyValue = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let supabaseAnonKey = ConfigNormalization.normalizeConfigValue(supabaseAnonKeyValue)
        else {
            return nil
        }

        return ExtensionSupabaseConfig(url: supabaseURL, anonKey: supabaseAnonKey)
    }
}

private struct ExtensionSupabaseConfig {
    let url: URL
    let anonKey: String
}
