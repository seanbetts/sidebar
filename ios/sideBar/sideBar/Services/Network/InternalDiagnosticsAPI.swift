import Foundation
import sideBarShared

/// Internal-only client for notification diagnostics endpoints.
public struct InternalDiagnosticsAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func getSnapshot() async throws -> InternalNotificationDiagnosticsSnapshot {
        try await client.request("internal/notification-diagnostics")
    }

    public func sendTestPush(installationId: String) async throws -> InternalNotificationTestPushResponse {
        try await client.request(
            "internal/notification-diagnostics/installations/\(installationId)/test-push",
            method: "POST"
        )
    }
}
