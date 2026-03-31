import Foundation

/// UI-test-only launch bootstrap that can start the app from an authenticated state.
enum UITestAuthBootstrap {
    static let accessTokenKey = "SIDEBAR_UI_TEST_ACCESS_TOKEN"
    static let userIdKey = "SIDEBAR_UI_TEST_USER_ID"
    static let forceStaleAuthKey = "SIDEBAR_UI_TEST_FORCE_STALE_AUTH"
    private static let fallbackAccessToken = "debug-stale-auth-token"
    private static let fallbackUserId = "debug-stale-auth-user"

    static func makeSeededSession(from environment: [String: String]) -> PlaceholderAuthSession? {
        if environment[forceStaleAuthKey] == "1" {
            return PlaceholderAuthSession(
                accessToken: trimmedValue(for: accessTokenKey, in: environment) ?? fallbackAccessToken,
                userId: trimmedValue(for: userIdKey, in: environment) ?? fallbackUserId,
                authState: .stale
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
