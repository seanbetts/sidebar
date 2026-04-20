import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class SettingsWriteQueueExecutorTests: XCTestCase {
    func testExecuteProviderKeyMutationLoadsRawSecretFromPendingSecretStore() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let api = SettingsWriteQueueExecutorAPISpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            pendingSecretStore: secretStore,
            pendingAssetStore: SettingsPendingAssetStoreSpy()
        )
        let payload = SettingsMutationPayload.providerKey(
            provider: "anthropic",
            rawSecretReference: "secret-ref-1"
        )
        secretStore.stage(rawSecret: Data("anthropic-key".utf8), reference: "secret-ref-1")

        try await executor.execute(write: queuedSettingsWrite(payload))

        XCTAssertEqual(secretStore.lookupReferences, ["secret-ref-1"])
        XCTAssertEqual(api.upsertedProviderKeys, [("anthropic", "anthropic-key")])
    }

    func testQueuedSettingsWriteEncodesEntityTypeSettings() throws {
        let payload = SettingsMutationPayload(name: "Ada")
        let write = queuedSettingsWrite(payload)

        XCTAssertEqual(write.entityType, WriteEntityType.settings.rawValue)
        XCTAssertEqual(write.entityId, payload.entityId)
    }

    func testQueuedProfileImageReferenceWriteTargetsSettingsEntityType() throws {
        let write = queuedProfileImageReferenceWrite(reference: "asset-ref-1")

        XCTAssertEqual(write.entityType, WriteEntityType.settings.rawValue)
        XCTAssertEqual(write.entityId, "profile-image")
    }
}

private func queuedSettingsWrite(_ payload: SettingsMutationPayload) -> PendingWriteRecord {
    let payloadData = try! JSONEncoder().encode(payload)
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.settings.rawValue,
        entityId: payload.entityId,
        payload: payloadData,
        serverSnapshot: nil,
        attempts: 0
    )
}

private func queuedProfileImageReferenceWrite(reference: String) -> PendingWriteRecord {
    let payload = ProfileImageReferenceWritePayload(reference: reference)
    let payloadData = try! JSONEncoder().encode(payload)
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.settings.rawValue,
        entityId: "profile-image",
        payload: payloadData,
        serverSnapshot: nil,
        attempts: 0
    )
}

private struct ProfileImageReferenceWritePayload: Codable, Equatable {
    let reference: String
}

@MainActor
private final class SettingsWriteQueueExecutorAPISpy: SettingsProviding {
    private(set) var upsertedProviderKeys: [(String, String)] = []

    func getSettings() async throws -> UserSettings {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        _ = update
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        upsertedProviderKeys.append((provider, apiKey))
        return ProviderKeyStatusResponse(provider: provider, hasKey: true, keyLast4: "1234")
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        _ = provider
        _ = source
        _ = skillId
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func deleteProfileImage() async throws {
        throw SettingsWriteQueueExecutorTestError.forced
    }
}

@MainActor
private final class SettingsPendingSecretStoreSpy {
    private var secrets: [String: Data] = [:]
    private(set) var lookupReferences: [String] = []

    func stage(rawSecret: Data, reference: String) {
        secrets[reference] = rawSecret
    }

    func lookup(reference: String) throws -> Data {
        lookupReferences.append(reference)
        guard let secret = secrets[reference] else {
            throw SettingsWriteQueueExecutorTestError.forced
        }
        return secret
    }
}

@MainActor
private final class SettingsPendingAssetStoreSpy {
    func stageProfileImage(data: Data, contentType: String, filename: String) throws -> String {
        _ = data
        _ = contentType
        _ = filename
        return "asset-ref-1"
    }
}

private enum SettingsWriteQueueExecutorTestError: Error {
    case forced
}
