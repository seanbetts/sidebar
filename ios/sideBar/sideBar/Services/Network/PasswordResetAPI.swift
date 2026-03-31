import Foundation
import sideBarShared

/// Defines the requirements for password reset request delivery.
public protocol PasswordResetRequesting {
    func requestPasswordReset(email: String) async throws
}

private struct PasswordResetRequestBody: Encodable {
    let email: String
}

/// API wrapper for starting password reset delivery from the product backend.
public struct PasswordResetAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func requestPasswordReset(email: String) async throws {
        try await client.requestVoid(
            "auth/password-reset/request",
            method: "POST",
            body: PasswordResetRequestBody(email: email)
        )
    }
}

extension PasswordResetAPI: PasswordResetRequesting {}
