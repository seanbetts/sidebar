import Foundation
import Supabase
import sideBarShared
enum SupabaseAuthRecovery {
    private static let supabaseSessionStorageKeys = ["supabase.auth.token", "supabase.session"]

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

        let description = error.localizedDescription.lowercased()
        if description.contains("invalid") && description.contains("refresh") {
            return true
        }
        if description.contains("refresh token") && description.contains("expired") {
            return true
        }
        if description.contains("jwt") && description.contains("expired") && description.contains("refresh") {
            return true
        }
        if description.contains("invalid") && description.contains("jwt") {
            return true
        }

        let mentionsAuthRejection = description.contains("unauthorized") || description.contains("forbidden")
        let mentionsSessionContext =
            description.contains("session") ||
            description.contains("refresh") ||
            description.contains("jwt")
        if mentionsAuthRejection && mentionsSessionContext {
            return true
        }
        return false
    }

    static func clearPersistedAuthState(stateStore: AuthStateStore) throws {
        try stateStore.clear()
        if let metadataStore = stateStore as? AuthMetadataStore {
            try metadataStore.removeAuthMetadataValue(forKey: AppStorageKeys.lastAuthTimestamp)
        }
        guard let keychainStore = stateStore as? KeychainAuthStateStore else {
            return
        }
        for key in supabaseSessionStorageKeys {
            try keychainStore.removeSessionData(forKey: key)
        }
    }
}
