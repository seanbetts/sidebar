import Foundation
import sideBarShared

/// Encodes a device token registration request.
public struct DeviceTokenRegisterRequest: Encodable {
    public let token: String
    public let platform: String
    public let environment: String
    public let capabilities: [String: Bool]?
}

/// Encodes a device token disable request.
public struct DeviceTokenDisableRequest: Encodable {
    public let token: String
}

/// Encodes a device token presence update request.
public struct DeviceTokenPresenceRequest: Encodable {
    public let token: String
    public let isForeground: Bool
    public let lastSeenAt: String?

    private enum CodingKeys: String, CodingKey {
        case token
        case isForeground = "is_foreground"
        case lastSeenAt = "last_seen_at"
    }
}

/// Defines device token API operations used by the app.
public protocol DeviceTokensProviding {
    func register(
        token: String,
        platform: String,
        environment: String,
        capabilities: [String: Bool]?
    ) async throws
    func disable(token: String) async throws
    func updatePresence(
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
        token: String,
        platform: String,
        environment: String,
        capabilities: [String: Bool]? = nil
    ) async throws {
        let payload = DeviceTokenRegisterRequest(
            token: token,
            platform: platform,
            environment: environment,
            capabilities: capabilities
        )
        try await client.requestVoid("device-tokens", method: "POST", body: payload)
    }

    public func disable(token: String) async throws {
        let payload = DeviceTokenDisableRequest(token: token)
        try await client.requestVoid("device-tokens", method: "DELETE", body: payload)
    }

    public func updatePresence(
        token: String,
        isForeground: Bool,
        lastSeenAt: String?
    ) async throws {
        let payload = DeviceTokenPresenceRequest(
            token: token,
            isForeground: isForeground,
            lastSeenAt: lastSeenAt
        )
        try await client.requestVoid("device-tokens/presence", method: "POST", body: payload)
    }
}

extension DeviceTokensAPI: DeviceTokensProviding {}
