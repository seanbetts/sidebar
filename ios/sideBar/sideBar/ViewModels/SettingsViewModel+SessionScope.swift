import Foundation

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
