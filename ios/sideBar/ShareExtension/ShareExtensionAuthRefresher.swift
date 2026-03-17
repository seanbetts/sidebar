import Foundation
import Supabase
@preconcurrency import sideBarShared

struct ShareExtensionSupabaseConfig {
    let url: URL
    let anonKey: String
}

/// Refreshes Supabase auth state inside the share extension when access tokens expire.
final class ShareExtensionAuthRefresher {
    private let keychain: KeychainAuthStateStore
    private let supabase: SupabaseClient
    private let refreshLeadTime: TimeInterval = 300

    init?(keychain: KeychainAuthStateStore, bundle: Bundle = .main) {
        guard let config = Self.loadConfig(from: bundle) else {
            return nil
        }
        self.keychain = keychain
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: SupabaseKeychainStorageBridge(stateStore: keychain),
            emitLocalSessionAsInitialSession: true
        )
        let supabase = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
        self.supabase = supabase
    }

    func ensureValidSession(forceRefresh: Bool = false) async -> Bool {
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

    static func shouldRefreshAccessToken(
        _ accessToken: String,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        JWTExpiry.shouldRefreshAccessToken(accessToken, now: now, leadTime: leadTime)
    }

    private static func loadConfig(from bundle: Bundle) -> ShareExtensionSupabaseConfig? {
        guard
            let supabaseURLValue = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let normalizedURL = ConfigNormalization.normalizeConfigValue(supabaseURLValue),
            let supabaseURL = ConfigNormalization.parseHTTPURL(from: normalizedURL),
            let supabaseAnonKeyValue = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let supabaseAnonKey = ConfigNormalization.normalizeConfigValue(supabaseAnonKeyValue)
        else {
            return nil
        }

        return ShareExtensionSupabaseConfig(url: supabaseURL, anonKey: supabaseAnonKey)
    }
}
