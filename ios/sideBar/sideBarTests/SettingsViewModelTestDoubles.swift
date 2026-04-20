import Foundation
import sideBarShared
@testable import sideBar

enum SettingsViewModelMockError: Error {
    case forced
}

@MainActor
struct MockSettingsAPI: SettingsProviding {
    let result: Result<UserSettings, Error>
    let tokenResult: Result<ShortcutsTokenResponse, Error>
    let updateResult: Result<UserSettings, Error>
    let profileImageResult: Result<Data, Error>
    let readRecorder: SettingsReadRecorder?
    let updateRecorder: UpdateRecorder?
    let providerKeyRecorder: ProviderKeyRecorder?

    init(
        result: Result<UserSettings, Error>,
        tokenResult: Result<ShortcutsTokenResponse, Error> = .failure(SettingsViewModelMockError.forced),
        updateResult: Result<UserSettings, Error> = .failure(SettingsViewModelMockError.forced),
        profileImageResult: Result<Data, Error> = .failure(SettingsViewModelMockError.forced),
        readRecorder: SettingsReadRecorder? = nil,
        updateRecorder: UpdateRecorder? = nil,
        providerKeyRecorder: ProviderKeyRecorder? = nil
    ) {
        self.result = result
        self.tokenResult = tokenResult
        self.updateResult = updateResult
        self.profileImageResult = profileImageResult
        self.readRecorder = readRecorder
        self.updateRecorder = updateRecorder
        self.providerKeyRecorder = providerKeyRecorder
    }

    func getSettings() async throws -> UserSettings {
        readRecorder?.getSettingsCallCount += 1
        return try result.get()
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        try tokenResult.get()
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        try tokenResult.get()
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateRecorder?.callCount += 1
        updateRecorder?.lastUpdate = update
        return try updateResult.get()
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.statusCallCount += 1
        providerKeyRecorder?.lastStatusProvider = provider
        let normalizedProvider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasKey = normalizedProvider.flatMap { providerKeyRecorder?.statusByProvider[$0] } ?? false
        return ProviderKeyStatusResponse(provider: normalizedProvider, hasKey: hasKey, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.upsertCallCount += 1
        providerKeyRecorder?.lastUpsertProvider = provider
        providerKeyRecorder?.lastUpsertApiKey = apiKey
        return ProviderKeyStatusResponse(provider: nil, hasKey: true, keyLast4: "1234")
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.deleteCallCount += 1
        providerKeyRecorder?.lastDeleteProvider = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func getProfileImage() async throws -> Data {
        try profileImageResult.get()
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func deleteProfileImage() async throws {
    }
}

struct MockSkillsAPI: SkillsProviding {
    let result: Result<SkillsResponse, Error>
    let installResult: Result<StoreSkillInstallResponse, Error>
    let uninstallResult: Result<StoreSkillInstallResponse, Error>
    let listRecorder: SkillsListRecorder?
    let installRecorder: SkillsInstallRecorder?
    let uninstallRecorder: SkillsUninstallRecorder?

    init(
        result: Result<SkillsResponse, Error>,
        installResult: Result<StoreSkillInstallResponse, Error> = .failure(SettingsViewModelMockError.forced),
        uninstallResult: Result<StoreSkillInstallResponse, Error> = .failure(SettingsViewModelMockError.forced),
        listRecorder: SkillsListRecorder? = nil,
        installRecorder: SkillsInstallRecorder? = nil,
        uninstallRecorder: SkillsUninstallRecorder? = nil
    ) {
        self.result = result
        self.installResult = installResult
        self.uninstallResult = uninstallResult
        self.listRecorder = listRecorder
        self.installRecorder = installRecorder
        self.uninstallRecorder = uninstallRecorder
    }

    func list() async throws -> SkillsResponse {
        listRecorder?.listCallCount += 1
        return try result.get()
    }

    func installStoreSkill(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput]
    ) async throws -> StoreSkillInstallResponse {
        installRecorder?.callCount += 1
        installRecorder?.lastSkillId = skillId
        installRecorder?.lastProviderKeys = providerKeys
        return try installResult.get()
    }

    func uninstallStoreSkill(
        skillId: String
    ) async throws -> StoreSkillInstallResponse {
        uninstallRecorder?.callCount += 1
        uninstallRecorder?.lastSkillId = skillId
        return try uninstallResult.get()
    }
}

final class UpdateRecorder {
    var callCount: Int = 0
    var lastUpdate: SettingsUpdate?
}

final class SettingsReadRecorder {
    var getSettingsCallCount: Int = 0
}

final class ProviderKeyRecorder {
    var statusCallCount: Int = 0
    var upsertCallCount: Int = 0
    var deleteCallCount: Int = 0
    var lastStatusProvider: String?
    var lastUpsertProvider: String?
    var lastUpsertApiKey: String?
    var lastDeleteProvider: String?
    var statusByProvider: [String: Bool] = [:]
}

final class SkillsInstallRecorder {
    var callCount: Int = 0
    var lastSkillId: String?
    var lastProviderKeys: [StoreSkillProviderKeyInput]?
}

final class SkillsUninstallRecorder {
    var callCount: Int = 0
    var lastSkillId: String?
}

final class SkillsListRecorder {
    var listCallCount: Int = 0
}

@MainActor
final class SettingsMutationQueueSpy {
    private(set) var enqueuedWrites: [PendingWriteRecord] = []

    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: T,
        serverSnapshot: ServerSnapshot?
    ) async throws {
        _ = serverSnapshot
        let encodedPayload = try JSONEncoder().encode(payload)
        enqueuedWrites.append(
            PendingWriteRecord(
                id: UUID(),
                operationType: operation.rawValue,
                entityType: entityType.rawValue,
                entityId: entityId,
                payload: encodedPayload,
                serverSnapshot: nil,
                attempts: 0
            )
        )
    }
}

extension SettingsMutationQueueSpy: SettingsWriteQueueEnqueuing {}
