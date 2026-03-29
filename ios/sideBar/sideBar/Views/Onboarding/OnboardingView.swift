import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Container for the Phase 1 onboarding wizard.
struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSoftwareKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var bottomAreaHeight: CGFloat = 0
    let onRouteToSignIn: () -> Void

    init(
        authSession: AuthSession,
        onboardingAPI: OnboardingProviding,
        settingsAPI: SettingsProviding,
        onRouteToSignIn: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(
                authSession: authSession,
                onboardingAPI: onboardingAPI,
                settingsAPI: settingsAPI
            )
        )
        self.onRouteToSignIn = onRouteToSignIn
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: DesignTokens.Animation.standard), value: viewModel.currentStep)
                .contentShape(Rectangle())
                .simultaneousGesture(backSwipeGesture)
        }
        .overlay(alignment: .topLeading) {
            if showsBackButton {
                backButton
                    .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .overlay(alignment: .bottom) {
            if OnboardingChromeLayoutPolicy.bottomAreaPlacement == .overlay {
                bottomArea
                    .background(DesignTokens.Colors.background)
                    .onboardingBottomAreaHeightReader()
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .interactiveDismissDisabled()
        .onOnboardingBottomAreaHeightChange { height in
            bottomAreaHeight = height
        }
#if canImport(UIKit)
        .modifier(OnboardingKeyboardSafeAreaModifier(isEnabled: OnboardingChromeLayoutPolicy.rootIgnoresKeyboardSafeArea))
#endif
        .onChange(of: viewModel.routeToSignIn) { _, shouldRouteToSignIn in
            guard shouldRouteToSignIn else { return }
            onRouteToSignIn()
            dismiss()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            isSoftwareKeyboardVisible = true
            keyboardHeight = keyboardHeight(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
            keyboardHeight = 0
        }
#endif
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .createAccount:
            CreateAccountStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .verifyEmail:
            VerifyEmailStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .profile:
            ProfileStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .chooseProvider:
            ChooseProviderStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .addApiKey:
            AddApiKeyStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .transition:
            TransitionStepView(
                viewModel: viewModel,
                dismiss: dismiss,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        }
    }

    private var effectiveBottomContentInset: CGFloat {
        OnboardingChromeLayoutPolicy.contentBottomInset(
            for: bottomAreaHeight,
            keyboardHeight: keyboardHeight
        )
    }

    private var layoutMode: OnboardingLayoutMode {
        isSoftwareKeyboardVisible ? .compact : .regular
    }

    private var showsBackButton: Bool {
        viewModel.currentStepHasBack
    }

    @ViewBuilder
    private var bottomArea: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode) {
                    Button(action: { viewModel.advance() }, label: {
                        Text("Get Started")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Button("Already have an account? Sign In", action: {
                        viewModel.routeToSignIn = true
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .createAccount:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode, reservesSecondarySpace: true) {
                    Button(action: {
                        Task { await viewModel.createAccount() }
                    }, label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(DesignTokens.Colors.background)
                            } else {
                                Text("Continue")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: 310)
                        .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!viewModel.isCreateAccountValid || viewModel.isLoading)
                    .opacity(viewModel.isCreateAccountValid ? 1.0 : 0.4)
                } secondary: {
                    Text(" ")
                        .font(.subheadline)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        case .verifyEmail:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                EmptyView()
            }
        case .profile:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode) {
                    Button(action: {
                        Task { await viewModel.saveProfile() }
                    }, label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Button("Skip for now", action: {
                        viewModel.skipProfile()
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .chooseProvider:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode) {
                    Button(action: { viewModel.advance() }, label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.selectedProvider == nil)
                    .opacity(viewModel.selectedProvider == nil ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: {
                        Task { await viewModel.skipProviderSetup() }
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .addApiKey:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode) {
                    Button(action: {
                        Task { await viewModel.validateAndSaveApiKey() }
                    }, label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(DesignTokens.Colors.background)
                            } else {
                                Text("Verify & Continue")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: 310)
                        .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.trimmedApiKey.isEmpty || viewModel.isLoading)
                    .opacity(viewModel.trimmedApiKey.isEmpty ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: {
                        Task { await viewModel.skipProviderSetup() }
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .transition:
            OnboardingBottomArea(
                layoutMode: layoutMode,
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(layoutMode: layoutMode, reservesSecondarySpace: true) {
                    Button(action: {
                        Task {
                            await viewModel.completeOnboarding()
                            dismiss()
                        }
                    }, label: {
                        Text("Meet sideBar")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, layoutMode.buttonVerticalPadding)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Text(" ")
                        .font(.subheadline)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard viewModel.currentStepHasBack,
                      value.translation.width > 90,
                      abs(value.translation.height) < 60 else {
                    return
                }
                viewModel.goBack()
            }
    }

    private var backButton: some View {
        Button(action: { viewModel.goBack() }, label: {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back")
                    .font(.body)
            }
            .foregroundStyle(.primary)
        })
        .frame(height: DesignTokens.Size.touchTarget)
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

#if canImport(UIKit)
    private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        return max(0, UIScreen.main.bounds.maxY - frame.minY)
    }
#endif
}

#if canImport(UIKit)
private struct OnboardingKeyboardSafeAreaModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}
#endif
