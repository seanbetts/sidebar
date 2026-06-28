import Foundation
import Supabase
import sideBarShared
enum SupabaseAuthRecovery {
    private static let supabaseSessionStorageKeys = ["supabase.auth.token", "supabase.session"]

    private struct PersistedAuthCleanupError: Error {
        let errors: [Error]
    }

    static func isAuthInvalid(_ error: Error) -> Bool {
        if error is URLError {
            return false
        }

        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .sessionNotFound,
                 .sessionExpired,
                 .refreshTokenNotFound,
                 .refreshTokenAlreadyUsed,
                 .invalidJWT,
                 .badJWT,
                 .noAuthorization:
                return true
            default:
                break
            }
        }

        return descriptionIndicatesInvalidAuth(error.localizedDescription.lowercased())
    }

    private static func descriptionIndicatesInvalidAuth(_ description: String) -> Bool {
        let invalidPatterns = [
            description.contains("invalid") && description.contains("refresh"),
            description.contains("refresh token") && description.contains("expired"),
            description.contains("session") && description.contains("expired"),
            description.contains("refresh token") && description.contains("revoked"),
            description.contains("jwt") && description.contains("expired") && description.contains("refresh"),
            description.contains("invalid") && description.contains("jwt")
        ]
        if invalidPatterns.contains(true) {
            return true
        }

        let mentionsAuthRejection = description.contains("unauthorized") || description.contains("forbidden")
        let mentionsSessionContext =
            description.contains("session") ||
            description.contains("refresh") ||
            description.contains("jwt")
        return mentionsAuthRejection && mentionsSessionContext
    }

    static func clearPersistedAuthState(stateStore: AuthStateStore) throws {
        var errors: [Error] = []
        do {
            try stateStore.clear()
        } catch {
            errors.append(error)
        }

        if let metadataStore = stateStore as? AuthMetadataStore {
            do {
                try metadataStore.removeAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp)
            } catch {
                errors.append(error)
            }
            do {
                try metadataStore.removeAuthMetadataValue(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
            } catch {
                errors.append(error)
            }
        }

        if let keychainStore = stateStore as? KeychainAuthStateStore {
            for key in supabaseSessionStorageKeys {
                do {
                    try keychainStore.removeSessionData(forKey: key)
                } catch {
                    errors.append(error)
                }
            }
        }

        if !errors.isEmpty {
            throw PersistedAuthCleanupError(errors: errors)
        }
    }

    static func clearPersistedAuthState(stateStore: AuthStateStore, userDefaults: UserDefaults) throws {
        do {
            try clearPersistedAuthState(stateStore: stateStore)
        } catch {
            userDefaults.removeObject(forKey: AppStorageKeys.lastAuthTimestamp)
            userDefaults.removeObject(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
            throw error
        }
        userDefaults.removeObject(forKey: AppStorageKeys.lastAuthTimestamp)
        userDefaults.removeObject(forKey: AppStorageKeys.authTimestampLegacyMigrationCompleted)
    }
}
