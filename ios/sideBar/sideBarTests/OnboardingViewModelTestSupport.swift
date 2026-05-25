import Foundation
@testable import sideBar

final class MockOnboardingAPI: OnboardingProviding {
    struct RecordedUpdate: Equatable {
        let status: OnboardingStatus?
        let profileBasicsSet: String?
        let secondaryTourSeen: String?
        let locationPermission: OnboardingPermissionState?
        let notificationsPermission: OnboardingPermissionState?
    }

    var getResult: Result<OnboardingState, Error> = .success(.default)
    var getResults: [Result<OnboardingState, Error>] = []
    var updateResult: Result<OnboardingState, Error> = .success(.default)
    var submitCalibrationAnswerResult: Result<OnboardingCalibrationActionResponse, Error> = .success(
        OnboardingCalibrationActionResponse(
            state: .default,
            calibration: .default,
            assistantIdentity: nil,
            assistantSoul: nil,
            confirmationText: nil
        )
    )
    var submitCalibrationAnswerResults: [Result<OnboardingCalibrationActionResponse, Error>] = []
    var regenerateCalibrationNameResult: Result<OnboardingCalibrationActionResponse, Error> = .success(
        OnboardingCalibrationActionResponse(
            state: .default,
            calibration: .default,
            assistantIdentity: nil,
            assistantSoul: nil,
            confirmationText: nil
        )
    )
    var regenerateCalibrationNameResults: [Result<OnboardingCalibrationActionResponse, Error>] = []
    var acceptCalibrationNameResult: Result<OnboardingCalibrationActionResponse, Error> = .success(
        OnboardingCalibrationActionResponse(
            state: .default,
            calibration: .default,
            assistantIdentity: nil,
            assistantSoul: nil,
            confirmationText: nil
        )
    )
    private(set) var updates: [RecordedUpdate] = []
    private(set) var getOnboardingCallCount = 0
    private(set) var submittedCalibrationAnswers: [(prompt: OnboardingCalibrationPrompt, answer: OnboardingCalibrationAnswer)] = []
    private(set) var regenerateCalibrationNameCallCount = 0
    private(set) var acceptCalibrationNameCallCount = 0

    func getOnboarding() async throws -> OnboardingState {
        getOnboardingCallCount += 1
        if !getResults.isEmpty {
            return try getResults.removeFirst().get()
        }
        return try getResult.get()
    }

    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState {
        updates.append(RecordedUpdate(
            status: update.status,
            profileBasicsSet: update.milestones?.profileBasicsSet,
            secondaryTourSeen: update.milestones?.secondaryTourSeen,
            locationPermission: update.permissions?.location,
            notificationsPermission: update.permissions?.notifications
        ))
        return try updateResult.get()
    }

    func submitCalibrationAnswer(
        _ prompt: OnboardingCalibrationPrompt,
        answer: OnboardingCalibrationAnswer
    ) async throws -> OnboardingCalibrationActionResponse {
        submittedCalibrationAnswers.append((prompt: prompt, answer: answer))
        if !submitCalibrationAnswerResults.isEmpty {
            return try submitCalibrationAnswerResults.removeFirst().get()
        }
        return try submitCalibrationAnswerResult.get()
    }

    func regenerateCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        regenerateCalibrationNameCallCount += 1
        if !regenerateCalibrationNameResults.isEmpty {
            return try regenerateCalibrationNameResults.removeFirst().get()
        }
        return try regenerateCalibrationNameResult.get()
    }

    func acceptCalibrationName() async throws -> OnboardingCalibrationActionResponse {
        acceptCalibrationNameCallCount += 1
        return try acceptCalibrationNameResult.get()
    }
}

@MainActor
final class MockLocationPermissionRequester: LocationPermissionRequesting {
    var currentState: OnboardingPermissionState = .notAsked
    var requestResult: OnboardingPermissionState = .granted
    private(set) var requestCount = 0

    func requestPermission() async -> OnboardingPermissionState {
        requestCount += 1
        currentState = requestResult
        return requestResult
    }
}

@MainActor
final class MockNotificationPermissionRequester: NotificationPermissionRequesting {
    var currentStateValue: OnboardingPermissionState = .notAsked
    var requestResult: OnboardingPermissionState = .granted
    private(set) var requestCount = 0
    private(set) var refreshCount = 0

    var currentState: OnboardingPermissionState {
        currentStateValue
    }

    func refreshCurrentState() async -> OnboardingPermissionState {
        refreshCount += 1
        return currentStateValue
    }

    func requestPermission() async -> OnboardingPermissionState {
        requestCount += 1
        currentStateValue = requestResult
        return requestResult
    }
}

final class OnboardingMockSettingsAPI: SettingsProviding {
    var settings = UserSettings(
        userId: "u1",
        communicationStyle: nil,
        workingRelationship: nil,
        name: nil,
        jobTitle: nil,
        employer: nil,
        dateOfBirth: nil,
        gender: nil,
        pronouns: nil,
        location: nil,
        profileImageUrl: nil,
        enabledSkills: []
    )
    var providerKeyStatus = ProviderKeyStatusResponse(
        provider: "anthropic",
        hasKey: false,
        keyLast4: nil
    )
    var shortcutsToken = ShortcutsTokenResponse(token: "shortcuts-token")
    var updateSettingsResult: Result<UserSettings, Error>?
    var upsertProviderKeyResult: Result<ProviderKeyStatusResponse, Error>?
    private(set) var updates: [SettingsUpdate] = []

    func getSettings() async throws -> UserSettings {
        settings
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updates.append(update)
        if let updateSettingsResult {
            settings = try updateSettingsResult.get()
            return settings
        }
        settings = UserSettings(
            userId: settings.userId,
            communicationStyle: update.communicationStyle ?? settings.communicationStyle,
            workingRelationship: update.workingRelationship ?? settings.workingRelationship,
            name: update.name ?? settings.name,
            jobTitle: update.jobTitle ?? settings.jobTitle,
            employer: update.employer ?? settings.employer,
            dateOfBirth: update.includeDateOfBirth ? update.dateOfBirth : (update.dateOfBirth ?? settings.dateOfBirth),
            gender: update.gender ?? settings.gender,
            pronouns: update.pronouns ?? settings.pronouns,
            location: update.location ?? settings.location,
            profileImageUrl: settings.profileImageUrl,
            assistantIdentity: update.assistantIdentity ?? settings.assistantIdentity,
            assistantIdentityMeta: settings.assistantIdentityMeta,
            assistantSoul: settings.assistantSoul,
            assistantSoulMeta: settings.assistantSoulMeta,
            aiPrimaryProvider: update.aiPrimaryProvider ?? settings.aiPrimaryProvider,
            aiPrimaryProviderHasKey: settings.aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: settings.aiPrimaryProviderKeyLast4,
            enabledSkills: update.enabledSkills ?? settings.enabledSkills,
            installedStoreSkills: settings.installedStoreSkills
        )
        return settings
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return providerKeyStatus
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        settings = UserSettings(
            userId: settings.userId,
            communicationStyle: settings.communicationStyle,
            workingRelationship: settings.workingRelationship,
            name: settings.name,
            jobTitle: settings.jobTitle,
            employer: settings.employer,
            dateOfBirth: settings.dateOfBirth,
            gender: settings.gender,
            pronouns: settings.pronouns,
            location: settings.location,
            profileImageUrl: settings.profileImageUrl,
            assistantIdentity: settings.assistantIdentity,
            assistantIdentityMeta: settings.assistantIdentityMeta,
            assistantSoul: settings.assistantSoul,
            assistantSoulMeta: settings.assistantSoulMeta,
            aiPrimaryProvider: provider,
            aiPrimaryProviderHasKey: true,
            aiPrimaryProviderKeyLast4: String(apiKey.suffix(4)),
            enabledSkills: settings.enabledSkills,
            installedStoreSkills: settings.installedStoreSkills
        )
        providerKeyStatus = ProviderKeyStatusResponse(
            provider: provider,
            hasKey: true,
            keyLast4: String(apiKey.suffix(4))
        )
        if let upsertProviderKeyResult {
            return try upsertProviderKeyResult.get()
        }
        return providerKeyStatus
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return providerKeyStatus
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: skillId.map { [$0] } ?? [],
                detachedAIProvider: false,
                deletedProviderKey: false
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: false,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: [],
                installedStoreSkills: [],
                aiPrimaryProvider: nil
            )
        )
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        shortcutsToken
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        shortcutsToken
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        Data()
    }

    func deleteProfileImage() async throws {}
}

final class DelayedProfileSettingsAPI: SettingsProviding {
    private let base = OnboardingMockSettingsAPI()
    var onUpdateStarted: (() -> Void)?
    var onUpdateCompleted: (() -> Void)?
    var updateDelayNanoseconds: UInt64 = 0

    func getSettings() async throws -> UserSettings {
        try await base.getSettings()
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        onUpdateStarted?()
        if updateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: updateDelayNanoseconds)
        }
        let settings = try await base.updateSettings(update)
        onUpdateCompleted?()
        return settings
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        try await base.getProviderKeyStatus(provider: provider)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        try await base.upsertProviderKey(provider: provider, apiKey: apiKey)
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        try await base.deleteProviderKey(provider: provider)
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        try await base.disconnectProviderConsumer(
            provider: provider,
            source: source,
            skillId: skillId
        )
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await base.getShortcutsToken()
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await base.rotateShortcutsToken()
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        try await base.uploadProfileImage(data: data, contentType: contentType, filename: filename)
    }

    func getProfileImage() async throws -> Data {
        try await base.getProfileImage()
    }

    func deleteProfileImage() async throws {
        try await base.deleteProfileImage()
    }
}

extension OnboardingState {
    static let `default` = OnboardingState(
        status: .notStarted,
        providerReady: false,
        currentOnboardingStep: .phase1Wizard,
        isOnboardingComplete: false,
        intent: nil,
        milestones: OnboardingMilestones(
            providerConnected: nil,
            firstOutcomeCompleted: nil,
            profileBasicsSet: nil,
            communicationStyleSet: nil,
            secondaryTourSeen: nil
        ),
        permissions: OnboardingPermissions(
            location: .notAsked,
            notifications: .notAsked
        ),
        lastPromptedAt: nil
    )
}

@MainActor
final class MockAuthSessionForOnboarding: AuthSession {
    var accessToken: String?
    var userId: String?
    var authState: AuthState = .signedOut
    var pendingVerificationEmail: String?
    var signUpError: Error?
    var verifyOTPError: Error?

    var authorizationToken: String? {
        authState == .active ? accessToken : nil
    }

    func signIn(email: String, password: String) async throws {
        _ = email
        _ = password
    }

    func signUp(email: String, password: String) async throws {
        _ = password
        if let signUpError {
            throw signUpError
        }
        pendingVerificationEmail = email
    }

    func verifyOTP(email: String, code: String) async throws {
        _ = email
        _ = code
        if let verifyOTPError {
            throw verifyOTPError
        }
        authState = .active
        userId = "test-user-id"
        accessToken = "test-token"
        pendingVerificationEmail = nil
    }

    func refreshSession() async {}

    func refreshSessionIfStale() async {}

    func signOut() async {
        accessToken = nil
        userId = nil
        authState = .signedOut
        pendingVerificationEmail = nil
    }
}
