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
    @EnvironmentObject var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    #endif
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    @State var sidebarSelection: AppSection?
    @State var primarySection: AppSection?
    @State var secondarySection: AppSection? = .chat
    @State var lastNonChatSection: AppSection?
    @AppStorage(AppStorageKeys.leftPanelExpanded) var isLeftPanelExpanded: Bool = true
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) var biometricUnlockEnabled: Bool = false
    @State var isSettingsPresented = false
    @State var phoneSelection: AppSection = .chat
    @State var isPhoneScratchpadPresented = false
    @State var isShortcutsPresented = false
    @State var didSetInitialSelection = false
    @State var didLoadSettings = false
    @State var isBiometricUnlocked = false
    @State var activeAlert: ActiveAlert?
    @State var pendingSessionExpiryAlert = false
    @State var pendingBiometricUnavailableAlert = false
    @State var isSigningOut = false
    @State var pendingReadyFileNotification: ReadyFileNotification?
    #if os(iOS)
    @AppStorage(AppStorageKeys.hasShownBiometricHint) var hasShownBiometricHint = false
    #endif
    @State var hasCompletedInitialSetup = false
    @State var backgroundedAt: Date?

    /// Grace period before requiring biometric re-authentication (30 seconds)
    let biometricGracePeriod: TimeInterval = 30

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
