import Foundation
@testable import sideBar

final class MockOnboardingAPI: OnboardingProviding {
    struct RecordedUpdate: Equatable {
        let status: OnboardingStatus?
        let locationPermission: OnboardingPermissionState?
        let notificationsPermission: OnboardingPermissionState?
    }

    var getResult: Result<OnboardingState, Error> = .success(.default)
    var updateResult: Result<OnboardingState, Error> = .success(.default)
    private(set) var updates: [RecordedUpdate] = []

    func getOnboarding() async throws -> OnboardingState {
        try getResult.get()
    }

    func updateOnboarding(_ update: OnboardingUpdate) async throws -> OnboardingState {
        updates.append(RecordedUpdate(
            status: update.status,
            locationPermission: update.permissions?.location,
            notificationsPermission: update.permissions?.notifications
        ))
        return try updateResult.get()
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

    func currentState() async -> OnboardingPermissionState {
        currentStateValue
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

    func getSettings() async throws -> UserSettings {
        settings
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        _ = update
        return settings
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return providerKeyStatus
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
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

extension OnboardingState {
    static let `default` = OnboardingState(
        status: .notStarted,
        providerReady: false,
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
