import Foundation

/// UI-test-only launch bootstrap that can start the app from an authenticated state.
enum UITestAuthBootstrap {
    static let accessTokenKey = "SIDEBAR_UI_TEST_ACCESS_TOKEN"
    static let userIdKey = "SIDEBAR_UI_TEST_USER_ID"

    static func makeSeededSession(from environment: [String: String]) -> PlaceholderAuthSession? {
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
