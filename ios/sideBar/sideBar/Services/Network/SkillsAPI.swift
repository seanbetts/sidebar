import Foundation
import sideBarShared

/// Defines the requirements for SkillsProviding.
public protocol SkillsProviding {
    func list() async throws -> SkillsResponse
    func installStoreSkill(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput]
    ) async throws -> StoreSkillInstallResponse
    func uninstallStoreSkill(
        skillId: String
    ) async throws -> StoreSkillInstallResponse
}

public extension SkillsProviding {
    func installStoreSkill(
        skillId _: String,
        providerKeys _: [StoreSkillProviderKeyInput]
    ) async throws -> StoreSkillInstallResponse {
        throw APIClientError.requestFailed(501)
    }

    func uninstallStoreSkill(
        skillId _: String
    ) async throws -> StoreSkillInstallResponse {
        throw APIClientError.requestFailed(501)
    }
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

    public func installStoreSkill(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput] = []
    ) async throws -> StoreSkillInstallResponse {
        try await client.request(
            "skills/store/install",
            method: "POST",
            body: StoreSkillInstallRequest(skillId: skillId, providerKeys: providerKeys)
        )
    }

    public func uninstallStoreSkill(skillId: String) async throws -> StoreSkillInstallResponse {
        try await client.request(
            "skills/store/uninstall",
            method: "POST",
            body: StoreSkillUninstallRequest(skillId: skillId)
        )
    }
}

extension SkillsAPI: SkillsProviding {}
