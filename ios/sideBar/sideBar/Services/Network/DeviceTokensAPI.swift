import Foundation
import sideBarShared

/// Encodes a device token registration request.
public struct DeviceTokenRegisterRequest: Encodable {
    public let token: String
    public let platform: String
    public let environment: String
}

/// Encodes a device token disable request.
public struct DeviceTokenDisableRequest: Encodable {
    public let token: String
}

/// Defines device token API operations used by the app.
public protocol DeviceTokensProviding {
    func register(token: String, platform: String, environment: String) async throws
    func disable(token: String) async throws
}

/// Concrete network client for device token endpoints.
public struct DeviceTokensAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func register(token: String, platform: String, environment: String) async throws {
        let payload = DeviceTokenRegisterRequest(token: token, platform: platform, environment: environment)
        try await client.requestVoid("device-tokens", method: "POST", body: payload)
    }

    public func disable(token: String) async throws {
        let payload = DeviceTokenDisableRequest(token: token)
        try await client.requestVoid("device-tokens", method: "DELETE", body: payload)
    }
}

extension DeviceTokensAPI: DeviceTokensProviding {}
