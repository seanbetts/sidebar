import Foundation
import sideBarShared

/// Encodes a device token registration request.
public struct DeviceTokenRegisterRequest: Encodable {
    public let installationId: String
    public let token: String
    public let platform: String
    public let environment: String
    public let capabilities: [String: Bool]?

    private enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case token
        case platform
        case environment
        case capabilities
    }
}

/// Encodes a device token disable request.
public struct DeviceTokenDisableRequest: Encodable {
    public let installationId: String
    public let token: String

    private enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case token
    }
}

/// Encodes a device token presence update request.
public struct DeviceTokenPresenceRequest: Encodable {
    public let installationId: String
    public let token: String
    public let isForeground: Bool
    public let lastSeenAt: String?

    private enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case token
        case isForeground = "is_foreground"
        case lastSeenAt = "last_seen_at"
    }
}

/// Defines device token API operations used by the app.
public protocol DeviceTokensProviding {
    func register(
        installationId: String,
        token: String,
        platform: String,
        environment: String,
        capabilities: [String: Bool]?
    ) async throws
    func disable(installationId: String, token: String) async throws
    func updatePresence(
        installationId: String,
        token: String,
        isForeground: Bool,
        lastSeenAt: String?
    ) async throws
}

/// Concrete network client for device token endpoints.
public struct DeviceTokensAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func register(
        installationId: String,
        token: String,
        platform: String,
        environment: String,
        capabilities: [String: Bool]? = nil
    ) async throws {
        let payload = DeviceTokenRegisterRequest(
            installationId: installationId,
            token: token,
            platform: platform,
            environment: environment,
            capabilities: capabilities
        )
        try await client.requestVoid("device-tokens", method: "POST", body: payload)
    }

    public func disable(installationId: String, token: String) async throws {
        let payload = DeviceTokenDisableRequest(
            installationId: installationId,
            token: token
        )
        try await client.requestVoid("device-tokens", method: "DELETE", body: payload)
    }

    public func updatePresence(
        installationId: String,
        token: String,
        isForeground: Bool,
        lastSeenAt: String?
    ) async throws {
        let payload = DeviceTokenPresenceRequest(
            installationId: installationId,
            token: token,
            isForeground: isForeground,
            lastSeenAt: lastSeenAt
        )
        try await client.requestVoid("device-tokens/presence", method: "POST", body: payload)
    }
}

extension DeviceTokensAPI: DeviceTokensProviding {}
