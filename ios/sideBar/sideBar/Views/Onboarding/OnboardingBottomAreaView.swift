import SwiftUI

struct OnboardingBottomAreaView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let dismiss: DismissAction

    var body: some View {
        switch viewModel.currentStep {
        case .welcome:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    primaryButton("Get Started", action: viewModel.advance)
                } secondary: {
                    Button("Already have an account? Sign In", action: routeToSignIn)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .createAccount:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode, reservesSecondarySpace: true) {
                    Button(action: createAccount, label: {
                        primaryLabel("Continue", showsProgress: viewModel.isLoading)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!viewModel.isCreateAccountValid || viewModel.isLoading)
                    .opacity(viewModel.isCreateAccountValid ? 1.0 : 0.4)
                } secondary: {
                    hiddenSecondaryLabel
                }
            }
        case .verifyEmail:
            progressContainer {
                EmptyView()
            }
        case .profile:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    primaryButton("Continue", action: saveProfile)
                } secondary: {
                    Button("Skip for now", action: viewModel.skipProfile)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .chooseProvider:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    primaryButton("Continue", action: viewModel.advance)
                        .disabled(viewModel.selectedProvider == nil)
                        .opacity(viewModel.selectedProvider == nil ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: skipProviderSetup)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .addApiKey:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    Button(action: validateAndSaveApiKey, label: {
                        primaryLabel("Verify & Continue", showsProgress: viewModel.isLoading)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.trimmedApiKey.isEmpty || viewModel.isLoading)
                    .opacity(viewModel.trimmedApiKey.isEmpty ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: skipProviderSetup)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .locationPermission:
            permissionArea(
                isResolved: viewModel.isLocationPermissionResolved,
                primaryAction: continueOrEnableLocation,
                secondaryAction: skipLocationPermission
            )
        case .notificationsPermission:
            permissionArea(
                isResolved: viewModel.isNotificationsPermissionResolved,
                primaryAction: continueOrEnableNotifications,
                secondaryAction: skipNotificationsPermission
            )
        case .finalStep:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode, reservesSecondarySpace: true) {
                    primaryButton("Meet sideBar", action: completeOnboarding)
                } secondary: {
                    hiddenSecondaryLabel
                }
            }
        }
    }

    @ViewBuilder
    private func progressContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        OnboardingBottomArea(
            layoutMode: layoutMode,
            totalSteps: viewModel.totalSteps,
            currentStep: viewModel.currentStepIndex,
            content: content
        )
    }

    @ViewBuilder
    private func permissionArea(
        isResolved: Bool,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        progressContainer {
            OnboardingActionArea(
                layoutMode: layoutMode,
                reservesSecondarySpace: isResolved
            ) {
                Button(action: primaryAction, label: {
                    primaryLabel(isResolved ? "Continue" : "Enable", showsProgress: viewModel.isLoading)
                })
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(viewModel.isLoading)
            } secondary: {
                if isResolved {
                    hiddenSecondaryLabel
                } else {
                    Button("Not now", action: secondaryAction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hiddenSecondaryLabel: some View {
        Text(" ")
            .font(.subheadline)
            .hidden()
            .accessibilityHidden(true)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action, label: {
            primaryLabel(title)
        })
        .buttonStyle(OnboardingPrimaryButtonStyle())
    }

    private func primaryLabel(
        _ title: String,
        showsProgress: Bool = false
    ) -> some View {
        Group {
            if showsProgress {
                ProgressView()
                    .tint(DesignTokens.Colors.background)
            } else {
                Text(title)
                    .font(.body.weight(.semibold))
            }
        }
        .frame(maxWidth: 310)
        .padding(.vertical, layoutMode.buttonVerticalPadding)
    }

    private func routeToSignIn() {
        viewModel.routeToSignIn = true
    }

    private func createAccount() {
        Task { await viewModel.createAccount() }
    }

    private func saveProfile() {
        Task { await viewModel.saveProfile() }
    }

    private func skipProviderSetup() {
        Task { await viewModel.skipProviderSetup() }
    }

    private func validateAndSaveApiKey() {
        Task { await viewModel.validateAndSaveApiKey() }
    }

    private func continueOrEnableLocation() {
        if viewModel.isLocationPermissionResolved {
            viewModel.advance()
        } else {
            Task { await viewModel.enableLocationPermission() }
        }
    }

    private func skipLocationPermission() {
        Task { await viewModel.skipLocationPermission() }
    }

    private func continueOrEnableNotifications() {
        if viewModel.isNotificationsPermissionResolved {
            viewModel.advance()
        } else {
            Task { await viewModel.enableNotificationsPermission() }
        }
    }

    private func skipNotificationsPermission() {
        Task { await viewModel.skipNotificationsPermission() }
    }

    private func completeOnboarding() {
        Task {
            await viewModel.completeOnboarding()
            dismiss()
        }
    }
}
