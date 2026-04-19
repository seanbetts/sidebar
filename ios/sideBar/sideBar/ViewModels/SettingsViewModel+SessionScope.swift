import Foundation
import os
import sideBarShared

struct SettingsRefreshFailure: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
extension SettingsViewModel {
    private static let settingsSessionExpiredMessage = "Session expired. Please sign in again."
    private static let settingsScopeLogger = Logger(subsystem: "sideBar", category: "SettingsSessionScope")

    public var assistantDisplayName: String {
        guard let rawName = settings?.assistantIdentity?.name else {
            return Self.defaultAssistantDisplayName
        }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultAssistantDisplayName : trimmed
    }

    func isBoundToCurrentAuthUser(settings: UserSettings) -> Bool {
        isBound(settings: settings, to: normalizedAuthUserId)
    }

    var normalizedAuthUserId: String? {
        normalizeUserId(currentAuthUserIdProvider())
    }

    var normalizedAuthorizedAuthUserId: String? {
        guard let currentAuthorizedUserIdProvider else { return nil }
        return normalizeUserId(currentAuthorizedUserIdProvider())
    }

    func normalizeUserId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func synchronizeInternalDiagnosticsSessionScope(with response: UserSettings) {
        let nextUserId = normalizeUserId(response.userId)
        defer { lastInternalDiagnosticsUserId = nextUserId }

        guard let lastInternalDiagnosticsUserId else {
            return
        }

        guard lastInternalDiagnosticsUserId != nextUserId else {
            return
        }

        internalDiagnosticsRevealTapCount = 0
        setInternalDiagnosticsLocallyUnlocked(false)
    }

    func isBound(settings: UserSettings, to expectedUserId: String?) -> Bool {
        guard let expectedUserId else {
            // Allow non-auth-scoped callers (tests/previews) that do not inject a user id provider.
            return true
        }
        return normalizeUserId(settings.userId) == expectedUserId
    }

    func resolveAuthorizedAuthUserIdForSettingsRequest() async -> Result<String?, SettingsRefreshFailure> {
        guard currentAuthorizedUserIdProvider != nil else {
            return .success(normalizedAuthUserId)
        }

        if let authorizedAuthUserId = normalizedAuthorizedAuthUserId {
            return .success(authorizedAuthUserId)
        }

        guard normalizedAuthUserId != nil else {
            return .success(nil)
        }

        Self.settingsScopeLogger.notice("Authorized settings session missing, attempting auth refresh before save")
        if let refreshAuthorizedSession {
            await refreshAuthorizedSession()
        }

        guard let authorizedAuthUserId = normalizedAuthorizedAuthUserId else {
            Self.settingsScopeLogger.error("Authorized settings session could not be recovered before save")
            return .failure(SettingsRefreshFailure(message: Self.settingsSessionExpiredMessage))
        }

        return .success(authorizedAuthUserId)
    }

    func reloadSettingsForCurrentAuthUser(
        expectedUserId: String?
    ) async -> Result<UserSettings, SettingsRefreshFailure> {
        do {
            Self.settingsScopeLogger.notice("Reloading settings for current auth user before save")
            let refreshed = try await settingsAPI.getSettings()
            guard isBound(settings: refreshed, to: expectedUserId) else {
                let expectedDescription = expectedUserId ?? "<none>"
                let actualDescription = normalizeUserId(refreshed.userId) ?? "<none>"
                let mismatchMessage =
                    "Reloaded settings do not match the active auth user " +
                    "expected=\(expectedDescription) actual=\(actualDescription)"
                Self.settingsScopeLogger.error(
                    "\(mismatchMessage, privacy: .private)"
                )
                return .failure(
                    SettingsRefreshFailure(
                        message: "Couldn't refresh the current account settings. Reopen Settings and try again."
                    )
                )
            }
            applySettingsResponse(refreshed)
            return .success(refreshed)
        } catch {
            let mappedError = settingsErrorMessage(
                for: error,
                operation: "settings.reloadBeforeSave",
                requestKind: .foregroundRead
            )
            Self.settingsScopeLogger.error(
                "Settings reload before save failed: \(mappedError, privacy: .public)"
            )
            return .failure(SettingsRefreshFailure(message: mappedError))
        }
    }

    func currentSettingsForSave() async -> (settings: UserSettings?, error: String?) {
        if let loaded = settings, isBound(settings: loaded, to: normalizedAuthUserId) {
            return (loaded, nil)
        }

        if settings != nil {
            Self.settingsScopeLogger.notice("Loaded settings snapshot is stale for current auth user, reloading before save")
        } else {
            Self.settingsScopeLogger.notice("No loaded settings snapshot available, reloading before save")
        }

        let expectedUserId: String?
        switch await resolveAuthorizedAuthUserIdForSettingsRequest() {
        case .success(let authorizedAuthUserId):
            expectedUserId = authorizedAuthUserId
        case .failure(let failure):
            return (nil, failure.message)
        }

        switch await reloadSettingsForCurrentAuthUser(expectedUserId: expectedUserId) {
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
