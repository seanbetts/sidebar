import Foundation
import sideBarShared

/// Defines the requirements for SkillsProviding.
public protocol SkillsProviding {
    func list() async throws -> SkillsResponse
}

/// API client for skills endpoints.
public struct SkillsAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func list() async throws -> SkillsResponse {
        try await client.request("skills")
    }
}

extension SkillsAPI: SkillsProviding {}
