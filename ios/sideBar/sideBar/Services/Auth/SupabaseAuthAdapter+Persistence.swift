import Foundation
import os
import sideBarShared

extension SupabaseAuthAdapter {
    public var canRestoreOfflineSession: Bool {
        do {
            let storedToken = try stateStore.loadAccessToken()
            let storedUserId = try stateStore.loadUserId()
            guard storedToken != nil, storedUserId != nil else { return false }
            return shouldAllowOfflineAccess(hasStoredToken: true)
        } catch {
            return false
        }
    }

    @discardableResult
    public func restoreOfflineSession() -> Bool {
        do {
            let storedToken = try stateStore.loadAccessToken()
            let storedUserId = try stateStore.loadUserId()
            guard let storedToken, let storedUserId else { return false }
            guard shouldAllowOfflineAccess(hasStoredToken: true) else { return false }
            restoreSession(accessToken: storedToken, userId: storedUserId)
            transitionToStale()
            return true
        } catch {
            return false
        }
    }

    static func sessionExpiryDate(from session: SupabaseSessionInfo) -> Date {
        if let jwtExpiry = jwtExpiryDate(from: session.accessToken) {
            return jwtExpiry
        }
        return resolveExpiryDate(from: session.expiresAt)
    }

    static func jwtExpiryDate(from accessToken: String) -> Date? {
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

    static func decodeJwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        let payload = String(segments[1])
        return base64UrlDecode(payload)
    }

    static func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

    func shouldAllowOfflineAccess(hasStoredToken: Bool) -> Bool {
        guard let lastAuthTimestamp = persistedLastAuthTimestamp() else {
            guard hasStoredToken else {
                diagnostics.record(AuthDiagnosticsEvent(
                    name: "offline_access_window",
                    metadata: ["reason": "missing_timestamp_without_token"]
                ))
                return false
            }
            guard !hasCompletedLegacyTimestampMigration() else {
                diagnostics.record(AuthDiagnosticsEvent(
                    name: "offline_access_window",
                    metadata: ["reason": "missing_timestamp_after_migration"]
                ))
                return false
            }
            updateLastAuthTimestamp(Date())
            markLegacyTimestampMigrationCompleted()
            diagnostics.record(AuthDiagnosticsEvent(
                name: "offline_access_window",
                metadata: ["reason": "legacy_timestamp_seeded"]
            ))
            return true
        }
        let lastAuthDate = Date(timeIntervalSince1970: lastAuthTimestamp)
        let isWithinWindow = Date().timeIntervalSince(lastAuthDate) <= AuthSessionPolicy.offlineAccessWindow
        diagnostics.record(AuthDiagnosticsEvent(
            name: "offline_access_window",
            metadata: ["reason": isWithinWindow ? "within_window" : "outside_window"]
        ))
        return isWithinWindow
    }

    func persistedLastAuthTimestamp() -> TimeInterval? {
        if let metadataStore = stateStore as? AuthMetadataStore,
           let timestampString = try? metadataStore.loadAuthMetadataValue(forKey: lastAuthTimestampKey),
           let timestamp = TimeInterval(timestampString),
           timestamp > 0 {
            return timestamp
        }

        let legacyTimestamp = userDefaults.double(forKey: lastAuthTimestampKey)
        if legacyTimestamp == 0 {
            return nil
        }

        if let metadataStore = stateStore as? AuthMetadataStore {
            try? metadataStore.saveAuthMetadataValue(String(legacyTimestamp), forKey: lastAuthTimestampKey)
            userDefaults.removeObject(forKey: lastAuthTimestampKey)
        }
        return legacyTimestamp
    }

    func updateLastAuthTimestamp(_ date: Date) {
        if let metadataStore = stateStore as? AuthMetadataStore {
            try? metadataStore.saveAuthMetadataValue(
                String(date.timeIntervalSince1970),
                forKey: lastAuthTimestampKey
            )
            userDefaults.removeObject(forKey: lastAuthTimestampKey)
            return
        }
        userDefaults.set(date.timeIntervalSince1970, forKey: lastAuthTimestampKey)
    }

    func hasCompletedLegacyTimestampMigration() -> Bool {
        if let metadataStore = stateStore as? AuthMetadataStore,
           (try? metadataStore.loadAuthMetadataValue(forKey: authTimestampLegacyMigrationCompletedKey)) == "true" {
            return true
        }
        return userDefaults.bool(forKey: authTimestampLegacyMigrationCompletedKey)
    }

    func markLegacyTimestampMigrationCompleted() {
        if let metadataStore = stateStore as? AuthMetadataStore {
            try? metadataStore.saveAuthMetadataValue("true", forKey: authTimestampLegacyMigrationCompletedKey)
            userDefaults.removeObject(forKey: authTimestampLegacyMigrationCompletedKey)
            return
        }
        userDefaults.set(true, forKey: authTimestampLegacyMigrationCompletedKey)
    }

    func loadPersistedRateLimitState() {
        failedLoginAttempts = userDefaults.integer(forKey: failedLoginAttemptsKey)
        let persistedLockoutEndTime = userDefaults.double(forKey: lockoutEndTimeKey)
        guard persistedLockoutEndTime > 0 else {
            lockoutEndTime = nil
            return
        }

        let endTime = Date(timeIntervalSince1970: persistedLockoutEndTime)
        if endTime > Date() {
            lockoutEndTime = endTime
        } else {
            failedLoginAttempts = 0
            lockoutEndTime = nil
            persistRateLimitState()
        }
    }

    func persistRateLimitState() {
        userDefaults.set(failedLoginAttempts, forKey: failedLoginAttemptsKey)
        if let lockoutEndTime {
            userDefaults.set(lockoutEndTime.timeIntervalSince1970, forKey: lockoutEndTimeKey)
        } else {
            userDefaults.removeObject(forKey: lockoutEndTimeKey)
        }
    }

    func recordError(_ message: String) {
        logger.error("\(message, privacy: .public)")
        authError = AuthErrorEvent(message: message)
    }

    public func clearAuthError() {
        authError = nil
    }

    private static func resolveExpiryDate(from expiresAt: TimeInterval) -> Date {
        let epochThreshold: TimeInterval = 1_000_000_000
        if expiresAt > epochThreshold {
            return Date(timeIntervalSince1970: expiresAt)
        }
        return Date(timeIntervalSinceNow: max(expiresAt, 0))
    }
}
