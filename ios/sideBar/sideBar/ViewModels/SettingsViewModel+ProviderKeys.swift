import Foundation

@MainActor
extension SettingsViewModel {
    private enum ProviderKeyOperationError: LocalizedError {
        case missingProvider
        case missingApiKey

        var errorDescription: String? {
            switch self {
            case .missingProvider:
                return "Provider is required"
            case .missingApiKey:
                return "API key is required"
            }
        }
    }

    public func providerKeyStatus(provider: String) async throws -> ProviderKeyStatusResponse {
        let normalizedProvider = try normalizedProviderIdentifier(provider)
        if settings?.aiPrimaryProvider == normalizedProvider {
            return ProviderKeyStatusResponse(
                provider: normalizedProvider,
                hasKey: settings?.aiPrimaryProviderHasKey ?? false,
                keyLast4: settings?.aiPrimaryProviderKeyLast4
            )
        }

        let status = try await settingsAPI.getProviderKeyStatus(provider: normalizedProvider)
        return ProviderKeyStatusResponse(
            provider: status.provider ?? normalizedProvider,
            hasKey: status.hasKey,
            keyLast4: status.keyLast4
        )
    }

    public func providerHasKey(provider: String) async throws -> Bool {
        let status = try await providerKeyStatus(provider: provider)
        return status.hasKey
    }

    public func saveProviderKey(
        provider: String,
        apiKey: String
    ) async throws -> ProviderKeyStatusResponse {
        let normalizedProvider = try normalizedProviderIdentifier(provider)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ProviderKeyOperationError.missingApiKey
        }

        let status = try await settingsAPI.upsertProviderKey(
            provider: normalizedProvider,
            apiKey: trimmedKey
        )
        let refreshed = try await settingsAPI.getSettings()
        applySettingsResponse(refreshed)
        return ProviderKeyStatusResponse(
            provider: status.provider ?? normalizedProvider,
            hasKey: status.hasKey,
            keyLast4: status.keyLast4
        )
    }

    public func deleteProviderKey(provider: String) async throws -> ProviderKeyStatusResponse {
        let normalizedProvider = try normalizedProviderIdentifier(provider)
        let status = try await settingsAPI.deleteProviderKey(provider: normalizedProvider)
        let refreshed = try await settingsAPI.getSettings()
        applySettingsResponse(refreshed)
        return ProviderKeyStatusResponse(
            provider: status.provider ?? normalizedProvider,
            hasKey: status.hasKey,
            keyLast4: status.keyLast4
        )
    }

    private func normalizedProviderIdentifier(_ provider: String) throws -> String {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else {
            throw ProviderKeyOperationError.missingProvider
        }
        return normalizedProvider
    }
}
