import Foundation

#if DEBUG
/// UI-test-only launch bootstrap that can start the app from an authenticated state.
enum UITestAuthBootstrap {
    static let bootstrapAuthKey = "SIDEBAR_UI_TEST_BOOTSTRAP_AUTH"
    static let accessTokenKey = "SIDEBAR_UI_TEST_ACCESS_TOKEN"
    static let userIdKey = "SIDEBAR_UI_TEST_USER_ID"
    static let forceStaleAuthKey = "SIDEBAR_UI_TEST_FORCE_STALE_AUTH"
    static let forcePasswordResetKey = "SIDEBAR_UI_TEST_FORCE_PASSWORD_RESET"
    private static let fallbackAccessToken = "debug-stale-auth-token"
    private static let fallbackUserId = "debug-stale-auth-user"

    static func makeSeededSession(from environment: [String: String]) -> PlaceholderAuthSession? {
        guard environment[bootstrapAuthKey] == "1" else { return nil }
        if environment[forceStaleAuthKey] == "1" {
            return PlaceholderAuthSession(
                accessToken: trimmedValue(for: accessTokenKey, in: environment) ?? fallbackAccessToken,
                userId: trimmedValue(for: userIdKey, in: environment) ?? fallbackUserId,
                authState: .staleRecoverable
            )
        }
        guard
            let accessToken = trimmedValue(for: accessTokenKey, in: environment),
            let userId = trimmedValue(for: userIdKey, in: environment)
        else {
            return nil
        }
        return PlaceholderAuthSession(
            accessToken: accessToken,
            userId: userId,
            authState: .active
        )
    }

    static func shouldForcePasswordReset(from environment: [String: String]) -> Bool {
        environment[forcePasswordResetKey] == "1"
    }

    private static func trimmedValue(
        for key: String,
        in environment: [String: String]
    ) -> String? {
        guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return rawValue
    }
}
#endif
