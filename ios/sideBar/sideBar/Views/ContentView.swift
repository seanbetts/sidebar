import SwiftUI
import Combine
import LocalAuthentication
import os
#if canImport(UIKit)
import UIKit
#endif

public enum AppSection: String, CaseIterable, Identifiable {
    case chat
    case notes
    case files
    case websites
    case settings
    case tasks

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var sidebarSelection: AppSection? = nil
    @State private var primarySection: AppSection? = nil
    @State private var secondarySection: AppSection? = .chat
    @State private var lastNonChatSection: AppSection? = nil
    @AppStorage(AppStorageKeys.leftPanelExpanded) private var isLeftPanelExpanded: Bool = true
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled: Bool = false
    @State private var isSettingsPresented = false
    @State private var phoneSelection: AppSection = .chat
    @State private var isPhoneScratchpadPresented = false
    @State private var isShortcutsPresented = false
    @State private var didSetInitialSelection = false
    @State private var didLoadSettings = false
    @State private var isBiometricUnlocked = false
    @State private var activeAlert: ActiveAlert?
    @State private var pendingSessionExpiryAlert = false
    @State private var pendingBiometricUnavailableAlert = false
    @State private var isSigningOut = false
    @State private var pendingReadyFileNotification: ReadyFileNotification?
    #if os(iOS)
    @AppStorage(AppStorageKeys.hasShownBiometricHint) private var hasShownBiometricHint = false
    #endif
    @State private var hasCompletedInitialSetup = false
    @State private var backgroundedAt: Date?

    /// Grace period before requiring biometric re-authentication (30 seconds)
    private let biometricGracePeriod: TimeInterval = 30

    public init() {
    }

    public var body: some View {
        Group {
            if let configError = environment.configError {
                ConfigErrorView(error: configError)
                    .onAppear { logStartup("ConfigErrorView appeared") }
            } else if !environment.isAuthenticated {
                LoginView()
                    .onAppear { logStartup("LoginView appeared") }
            } else {
                signedInContent
                    .onAppear { logStartup("SignedInContent appeared") }
            }
        }
    }

}
