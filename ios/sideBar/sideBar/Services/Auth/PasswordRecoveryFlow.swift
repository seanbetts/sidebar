import Foundation

/// Signed-out recovery state presented while the user completes a password reset.
public enum PasswordResetState: Equatable, Sendable {
    case enterNewPassword
}

/// Starts and completes password recovery after the provider redirects back with recovery credentials.
public protocol PasswordRecoveryManaging: AnyObject {
    /// Restores a recovery session from a provider callback URL.
    func startRecoverySession(from url: URL) async throws

    /// Updates the password for the active recovery session.
    func completePasswordReset(newPassword: String) async throws
}

enum PasswordRecoveryURLMatcher {
    static func matches(_ url: URL) -> Bool {
        let parameters = parameters(from: url)
        guard parameters["type"] == "recovery" else { return false }
        if let code = parameters["code"], !code.isEmpty {
            return true
        }
        let accessToken = parameters["access_token"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshToken = parameters["refresh_token"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !accessToken.isEmpty && !refreshToken.isEmpty
    }

    private static func parameters(from url: URL) -> [String: String] {
        var parameters: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems?.forEach { item in
                parameters[item.name] = item.value ?? ""
            }
            if let fragment = components.fragment {
                parseQueryString(fragment).forEach { key, value in
                    parameters[key] = value
                }
            }
        }

        return parameters
    }

    private static func parseQueryString(_ raw: String) -> [String: String] {
        raw
            .split(separator: "&")
            .reduce(into: [:]) { partialResult, pair in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(parts.first ?? "")
                let value = parts.count > 1 ? String(parts[1]) : ""
                guard !key.isEmpty else { return }
                partialResult[key.removingPercentEncoding ?? key] = value.removingPercentEncoding ?? value
            }
    }
}
