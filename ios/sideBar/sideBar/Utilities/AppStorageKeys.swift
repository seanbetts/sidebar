import Foundation

public enum AppStorageKeys {
    public nonisolated static let lastSelectedSection = "sidebar.lastSelectedSection"
    public nonisolated static let lastConversationId = "sidebar.lastConversationId"
    public nonisolated static let sidebarWidth = "sidebar.width"
    public nonisolated static let rightSidebarWidth = "sidebar.rightWidth"
    public nonisolated static let leftPanelExpanded = "sidebar.leftPanelExpanded"
    public nonisolated static let workspaceExpanded = "sidebar.workspaceExpanded"
    public nonisolated static let workspaceExpandedByRotation = "sidebar.workspaceExpandedByRotation"
    public nonisolated static let themeMode = "sidebar.themeMode"
    public nonisolated static let biometricUnlockEnabled = "sidebar.biometricUnlockEnabled"
    public nonisolated static let weatherUsesFahrenheit = "sidebar.weatherUsesFahrenheit"
    public nonisolated static let appTextSize = "sidebar.appTextSize"
    public nonisolated static let settingsSelectedSection = "sidebar.settingsSelectedSection"
    public nonisolated static let settingsSelectedTab = "sidebar.settingsSelectedTab"
    public nonisolated static let lastAuthTimestamp = "sidebar.lastAuthTimestamp"
    public nonisolated static let authTimestampLegacyMigrationCompleted =
        "sidebar.authTimestampLegacyMigrationCompleted"
    public nonisolated static let lastSignInEmail = "sidebar.lastSignInEmail"
    public nonisolated static let failedLoginAttempts = "sidebar.auth.failedLoginAttempts"
    public nonisolated static let lockoutEndTime = "sidebar.auth.lockoutEndTime"
    public nonisolated static let cacheScopeUserId = "sidebar.cacheScopeUserId"
    public nonisolated static let taskNotificationAccountGenerationId =
        "sidebar.taskNotificationAccountGenerationId"
    public nonisolated static let widgetAuthStateMirror = "sidebar.widgetAuthStateMirror"
    public nonisolated static let widgetAuthDisplayStateMirror = "sidebar.widgetAuthDisplayStateMirror"
    public nonisolated static let deviceInstallationId = "sidebar.deviceInstallationId"
    public nonisolated static let hasShownBiometricHint = "sidebar.hasShownBiometricHint"
    public nonisolated static let onboardingStatus = "sidebar.onboardingStatus"
    public nonisolated static let internalDiagnosticsUnlocked = "sidebar.internalDiagnosticsUnlocked"
    public nonisolated static let workspaceRestorationPhone = "sidebar.workspaceRestoration.phone.v1"
    public nonisolated static let workspaceRestorationWorkspace = "sidebar.workspaceRestoration.workspace.v1"
    public nonisolated static let workspaceRestorationDueTodayAutoOpenDate =
        "sidebar.workspaceRestoration.dueTodayAutoOpenDate.v1"
}
