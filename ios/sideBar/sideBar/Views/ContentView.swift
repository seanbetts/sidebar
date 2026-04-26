import SwiftUI
import Combine
import LocalAuthentication
import os
#if canImport(UIKit)
import UIKit
#endif

public struct ContentView: View {
    @EnvironmentObject var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    #endif
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    @State var sidebarSelection: AppSection?
    @AppStorage(AppStorageKeys.leftPanelExpanded) var isLeftPanelExpanded: Bool = true
    @AppStorage(AppStorageKeys.workspaceExpanded) var isWorkspaceExpanded: Bool = false
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) var biometricUnlockEnabled: Bool = false
    @State var isSettingsPresented = false
    @State var phoneSelection: AppSection = .chat
    @State var compactPhoneTabSelection: CompactPhoneTab = .section(.chat)
    @State var compactPhoneMoreNavigationPath: [AppSection] = []
    @State var compactPhoneChatSearchQuery: String = ""
    @State var compactPhoneSkillsStoreSearchQuery: String = ""
    @State var isCompactPhoneSearchDockExplicitlyExpanded = false
    @State var isCompactPhoneSoftwareKeyboardVisible = false
    @State var isPhoneScratchpadPresented = false
    @State var isMorningDigestPresented = false
    @State var isShortcutsPresented = false
    @State var didEnsureInitialPhoneChatInterface = false
    @State var didSetInitialSelection = false
    @State var didLoadSettings = false
    @State var activeAlert: ActiveAlert?
    @State var pendingBiometricUnavailableAlert = false
    @State var isSigningOut = false
    @State var pendingReadyFileNotification: ReadyFileNotification?
    @State var workspaceExpandedPreviousLeftPanelExpanded: Bool?
    #if os(iOS)
    @State var lastWorkspaceIsPortrait: Bool?
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if os(iOS)
    @AppStorage(AppStorageKeys.hasShownBiometricHint) var hasShownBiometricHint = false
    #endif
    @State var hasCompletedInitialSetup = false
    @State private var showOnboarding = false
    @State private var suppressAutomaticOnboarding = false
    @AppStorage(AppStorageKeys.onboardingStatus) private var onboardingStatusRaw = OnboardingStatus.notStarted.rawValue

    public init() {
    }

    public var body: some View {
        onboardingPresentationContainer
            .onAppear {
                syncOnboardingPresentation()
            }
            .onChange(of: environment.authState) { _, newValue in
                handleRootAuthStateChange(newValue)
                syncOnboardingPresentation()
            }
            .onChange(of: onboardingStatusRaw) { _, _ in
                syncOnboardingPresentation()
            }
            .onChange(of: environment.passwordResetState) { _, passwordResetState in
                if passwordResetState != nil {
                    showOnboarding = false
                }
                syncOnboardingPresentation()
            }
            .onChange(of: scenePhase) { _, _ in
                syncOnboardingPresentation()
            }
            .appTextSize()
    }

    @ViewBuilder
    private var rootContent: some View {
        Group {
            if let configError = environment.configError {
                ConfigErrorView(error: configError)
                    .onAppear { logStartup("ConfigErrorView appeared") }
            } else if environment.passwordResetState != nil {
                PasswordResetCompletionView()
                    .environmentObject(environment)
                    .onAppear { logStartup("PasswordResetCompletionView appeared") }
            } else if environment.authState == .reauthenticationRequired {
                ReauthenticationRequiredView {
                    Task { await environment.beginSignOut() }
                }
                .onAppear { logStartup("ReauthenticationRequiredView appeared") }
            } else if environment.authState == .signedOut {
                switch OnboardingPresentation.signedOutContent(
                    authState: environment.authState,
                    isOnboardingPresented: showOnboarding
                ) {
                case .login:
                    LoginView(
                        initialPasswordResetNotice: environment.passwordResetSuccessMessage,
                        initialPasswordResetNoticeDetail: environment.passwordResetSuccessDetail,
                        onConsumePasswordResetNotice: {
                            environment.passwordResetSuccessMessage = nil
                            environment.passwordResetSuccessDetail = nil
                        },
                        shouldAutofocusEmail: LoginFocusPolicy.shouldAutofocusEmail(
                            isOnboardingPresented: showOnboarding
                        ),
                        onStartOnboarding: presentOnboardingFromLogin
                    )
                        .onAppear { logStartup("LoginView appeared") }
                case .onboardingBackdrop:
                    signedOutOnboardingBackdrop
                        .onAppear { logStartup("OnboardingBackdrop appeared") }
                }
            } else {
                signedInContent
                    .onAppear { logStartup("SignedInContent appeared") }
            }
        }
    }

    private var onboardingPresentationContainer: some View {
        let content = AnyView(rootContent)
#if os(macOS)
        return AnyView(content.sheet(
            isPresented: $showOnboarding,
            onDismiss: handleOnboardingDismissed
        ) {
            OnboardingSheetCanvas {
                onboardingSheet
            }
        })
#else
        switch onboardingPresentationStyle {
        case .fullScreenCover:
            return AnyView(content.fullScreenCover(
                isPresented: $showOnboarding,
                onDismiss: handleOnboardingDismissed
            ) {
                onboardingSheet
            })
        case .sheet:
            return AnyView(content.sheet(
                isPresented: $showOnboarding,
                onDismiss: handleOnboardingDismissed
            ) {
                onboardingSheet
            })
        }
#endif
    }

    private var onboardingSheet: some View {
        OnboardingView(
            authSession: environment.container.authSession,
            onboardingAPI: environment.container.onboardingAPI,
            settingsAPI: environment.container.settingsAPI,
            onSettingsUpdated: { settings in
                environment.settingsViewModel.applySettingsResponse(settings)
            },
            onOnboardingUpdated: { state in
                environment.settingsViewModel.setOnboardingState(state)
            },
            onRouteToSignIn: {
                suppressAutomaticOnboarding = true
            },
            onComplete: handleOnboardingCompleted
        )
    }

    private var onboardingStatus: OnboardingStatus {
        OnboardingStatus(rawValue: onboardingStatusRaw) ?? .notStarted
    }

    private var isTestingOnboarding: Bool {
        OnboardingPresentation.isTestingOnboardingEnabled()
    }

    private var shouldAutoPresentOnboarding: Bool {
        guard environment.configError == nil, !suppressAutomaticOnboarding else {
            return false
        }
        guard environment.passwordResetState == nil else {
            return false
        }
        return OnboardingPresentation.shouldPresent(
            authState: environment.authState,
            onboardingStatus: onboardingStatus,
            isTestingOnboarding: isTestingOnboarding
        )
    }

    var signedInOnboardingRecoveryState: OnboardingPresentation.SignedInRecoveryState {
        OnboardingPresentation.signedInRecoveryState(
            authState: environment.authState,
            onboardingState: environment.settingsViewModel.onboardingState
        )
    }

    private var onboardingPresentationStyle: OnboardingPresentation.Style {
#if canImport(UIKit)
        OnboardingPresentation.style(for: UIDevice.current.userInterfaceIdiom)
#else
        .sheet
#endif
    }

    private func syncOnboardingPresentation() {
        if environment.passwordResetState != nil {
            showOnboarding = false
            return
        }
        guard !showOnboarding else { return }
        if shouldAutoPresentOnboarding {
            showOnboarding = true
        }
    }

    private func handleRootAuthStateChange(_ authState: AuthState) {
        guard Self.shouldResetSignedInBootstrapState(authState: authState) else { return }
        didEnsureInitialPhoneChatInterface = false
        didLoadSettings = false
    }

    private func handleOnboardingDismissed() {
        showOnboarding = false
        if isTestingOnboarding {
            suppressAutomaticOnboarding = true
        }
    }

    private func handleOnboardingCompleted() {
        if isTestingOnboarding {
            suppressAutomaticOnboarding = true
        }
        showOnboarding = false
        Task {
            guard environment.authState == .active else { return }
            await environment.settingsViewModel.load(force: true)
            await environment.settingsViewModel.loadOnboarding(force: true)
            await environment.settingsViewModel.loadProfileImage()
        }
    }

    private func presentOnboardingFromLogin() {
        suppressAutomaticOnboarding = false
        showOnboarding = true
    }

    private var signedOutOnboardingBackdrop: some View {
        DesignTokens.Colors.background
            .ignoresSafeArea()
    }

}
