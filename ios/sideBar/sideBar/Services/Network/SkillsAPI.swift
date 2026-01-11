import Foundation

public protocol SkillsProviding {
    func list() async throws -> SkillsResponse
}

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
