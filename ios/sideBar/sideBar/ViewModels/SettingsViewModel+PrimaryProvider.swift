import Foundation

@MainActor
extension SettingsViewModel {
    public var supportedPrimaryProviders: [AIPrimaryProvider] {
        AIPrimaryProvider.allCases
    }

    public func savePrimaryProvider(_ provider: AIPrimaryProvider) async {
        guard let current = settings else { return }
        if current.aiPrimaryProvider == provider.rawValue {
            return
        }

        setPrimaryProviderSaving(true)
        setPrimaryProviderError(nil)
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(aiPrimaryProvider: provider.rawValue)
            )
            applySettingsResponse(response)
        } catch {
            setPrimaryProviderError(error.localizedDescription)
        }
        setPrimaryProviderSaving(false)
    }

    public func savePrimaryProviderKey(
        provider: AIPrimaryProvider,
        apiKey: String
    ) async -> Bool {
        setPrimaryProviderSaving(true)
        setPrimaryProviderError(nil)
        do {
            _ = try await saveProviderKey(provider: provider.rawValue, apiKey: apiKey)
            setPrimaryProviderSaving(false)
            return true
        } catch {
            setPrimaryProviderError(error.localizedDescription)
            setPrimaryProviderSaving(false)
            return false
        }
    }

    public func deletePrimaryProviderKey(provider: AIPrimaryProvider) async {
        setPrimaryProviderSaving(true)
        setPrimaryProviderError(nil)
        do {
            _ = try await deleteProviderKey(provider: provider.rawValue)
        } catch {
            setPrimaryProviderError(error.localizedDescription)
        }
        setPrimaryProviderSaving(false)
    }
}
