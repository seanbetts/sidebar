import Foundation

struct SettingsRefreshFailure: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
extension SettingsViewModel {
    public var assistantDisplayName: String {
        guard let rawName = settings?.assistantIdentity?.name else {
            return Self.defaultAssistantDisplayName
        }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultAssistantDisplayName : trimmed
    }

    func isBoundToCurrentAuthUser(settings: UserSettings) -> Bool {
        guard let authUserId = normalizedAuthUserId else {
            // Allow non-auth-scoped callers (tests/previews) that do not inject a user id provider.
            return true
        }
        return normalizeUserId(settings.userId) == authUserId
    }

    var normalizedAuthUserId: String? {
        normalizeUserId(currentAuthUserIdProvider())
    }

    func normalizeUserId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func reloadSettingsForCurrentAuthUser() async -> Result<UserSettings, SettingsRefreshFailure> {
        do {
            let refreshed = try await settingsAPI.getSettings()
            applySettingsResponse(refreshed)
            guard isBoundToCurrentAuthUser(settings: refreshed) else {
                return .failure(
                    SettingsRefreshFailure(
                        message: "Couldn't refresh the current account settings. Reopen Settings and try again."
                    )
                )
            }
            return .success(refreshed)
        } catch {
            return .failure(SettingsRefreshFailure(message: error.localizedDescription))
        }
    }

    func currentSettingsForSave() async -> (settings: UserSettings?, error: String?) {
        if let loaded = settings, isBoundToCurrentAuthUser(settings: loaded) {
            return (loaded, nil)
        }

        switch await reloadSettingsForCurrentAuthUser() {
        case .success(let refreshed):
            return (refreshed, nil)
        case .failure(let failure):
            return (nil, failure.message)
        }
    }

    func normalizeEnabledSkills(_ enabledSkills: [String]) -> [String] {
        let allowedIds = Set(skills.map(\.id))
        let requiredIds = Set(skills.filter { !$0.userToggleable }.map(\.id))
        var seen: Set<String> = []
        var normalized: [String] = []

        for id in enabledSkills where allowedIds.contains(id) {
            if !seen.contains(id) {
                normalized.append(id)
                seen.insert(id)
            }
        }

        for id in skills.map(\.id) where requiredIds.contains(id) {
            if !seen.contains(id) {
                normalized.append(id)
                seen.insert(id)
            }
        }

        return normalized
    }
}
