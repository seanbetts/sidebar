import Foundation
import Supabase
import sideBarShared

struct SafariExtensionSupabaseConfig {
    let url: URL
    let anonKey: String
}

/// Refreshes shared Supabase auth state for Safari extension URL saves.
final class SafariExtensionAuthRefresher {
    private let keychain: KeychainAuthStateStore
    private let supabase: SupabaseClient
    private let refreshLeadTime: TimeInterval = 300

    init?(keychain: KeychainAuthStateStore, bundle: Bundle = .main) {
        guard let config = Self.loadConfig(from: bundle) else {
            return nil
        }
        self.keychain = keychain
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: SafariExtensionSupabaseKeychainStorage(stateStore: keychain),
            emitLocalSessionAsInitialSession: true
        )
        self.supabase = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: authOptions)
        )
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

    private static func shouldRefreshAccessToken(
        _ accessToken: String,
        now: Date = Date(),
        leadTime: TimeInterval
    ) -> Bool {
        guard let expiry = jwtExpiryDate(from: accessToken) else {
            return true
        }
        return expiry.timeIntervalSince(now) <= leadTime
    }

    private static func jwtExpiryDate(from accessToken: String) -> Date? {
        guard let payloadData = decodeJwtPayload(accessToken) else {
            return nil
        }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: payloadData, options: []),
            let payload = jsonObject as? [String: Any]
        else {
            return nil
        }
        if let exp = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let expString = payload["exp"] as? String,
           let exp = TimeInterval(expString) {
            return Date(timeIntervalSince1970: exp)
        }
        return nil
    }

    private static func decodeJwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        return base64UrlDecode(payload)
    }

    private static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

    private static func loadConfig(from bundle: Bundle) -> SafariExtensionSupabaseConfig? {
        guard
            let supabaseURLValue = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let normalizedURL = normalizeConfigValue(supabaseURLValue),
            let supabaseURL = parseHTTPURL(from: normalizedURL),
            let supabaseAnonKeyValue = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let supabaseAnonKey = normalizeConfigValue(supabaseAnonKeyValue)
        else {
            return nil
        }

        return SafariExtensionSupabaseConfig(url: supabaseURL, anonKey: supabaseAnonKey)
    }

    private static func normalizeConfigValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }
        if trimmed.hasPrefix("${") && trimmed.hasSuffix("}") {
            return nil
        }
        return trimmed.replacingOccurrences(of: "\\/", with: "/")
    }

    private static func parseHTTPURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}

private final class SafariExtensionSupabaseKeychainStorage: AuthLocalStorage, @unchecked Sendable {
    private let stateStore: KeychainAuthStateStore

    init(stateStore: KeychainAuthStateStore) {
        self.stateStore = stateStore
    }

    func store(key: String, value: Data) throws {
        try stateStore.saveSessionData(value, forKey: key)
    }

    func retrieve(key: String) throws -> Data? {
        try stateStore.loadSessionData(forKey: key)
    }

    func remove(key: String) throws {
        try stateStore.removeSessionData(forKey: key)
    }
}

enum SafariExtensionAuthCoordinator {
    static func forceRefreshAccessToken() async -> Bool {
        let keychain = ExtensionAuthStateStoreFactory.makeSharedStore()
        guard let refresher = SafariExtensionAuthRefresher(keychain: keychain) else {
            return false
        }
        return await refresher.ensureValidSession(forceRefresh: true)
    }
}
