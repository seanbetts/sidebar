import SwiftUI

struct OnboardingPermissionActionState: Equatable {
    let primaryTitle: String
    let hidesSecondaryAction: Bool

    static func resolve(
        isResolved: Bool,
        permissionState: OnboardingPermissionState
    ) -> OnboardingPermissionActionState {
        if isResolved && permissionState == .granted {
            return OnboardingPermissionActionState(
                primaryTitle: "Continue",
                hidesSecondaryAction: true
            )
        }

        return OnboardingPermissionActionState(
            primaryTitle: "Enable",
            hidesSecondaryAction: false
        )
    }
}

struct OnboardingBottomAreaView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let onComplete: () -> Void

    var body: some View {
        switch viewModel.currentStep {
        case .welcome:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    primaryButton("Get Started", action: startOnboarding)
                } secondary: {
                    secondaryTextLink("Already have an account? Sign In", action: routeToSignIn)
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
                    secondaryTextLink("Skip for now", action: viewModel.skipProfile)
                }
            }
        case .chooseProvider:
            progressContainer {
                OnboardingActionArea(layoutMode: layoutMode) {
                    primaryButton("Continue", action: continueFromChooseProvider)
                        .disabled(viewModel.selectedProvider == nil)
                        .opacity(viewModel.selectedProvider == nil ? 0.4 : 1.0)
                } secondary: {
                    secondaryTextLink("Skip for now", action: skipProviderSetup)
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
                    secondaryTextLink("Skip for now", action: skipProviderSetup)
                }
            }
        case .locationPermission:
            permissionArea(
                actionState: OnboardingPermissionActionState.resolve(
                    isResolved: viewModel.isLocationPermissionResolved,
                    permissionState: viewModel.locationPermissionState
                ),
                primaryAction: continueOrEnableLocation,
                secondaryAction: skipLocationPermission
            )
        case .notificationsPermission:
            permissionArea(
                actionState: OnboardingPermissionActionState.resolve(
                    isResolved: viewModel.isNotificationsPermissionResolved,
                    permissionState: viewModel.notificationsPermissionState
                ),
                isRefreshing: viewModel.isRefreshingNotificationsPermissionState,
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
        actionState: OnboardingPermissionActionState,
        isRefreshing: Bool = false,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        progressContainer {
            OnboardingActionArea(
                layoutMode: layoutMode,
                reservesSecondarySpace: actionState.hidesSecondaryAction
            ) {
                Button(action: primaryAction, label: {
                    primaryLabel(
                        actionState.primaryTitle,
                        showsProgress: viewModel.isLoading || isRefreshing
                    )
                })
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(viewModel.isLoading || isRefreshing)
            } secondary: {
                if actionState.hidesSecondaryAction || isRefreshing {
                    hiddenSecondaryLabel
                } else {
                    secondaryTextLink("Not now", action: secondaryAction)
                }
            }
        }
    }

    private var hiddenSecondaryLabel: some View {
        Text(" ")
            .appFont(.body)
            .hidden()
            .accessibilityHidden(true)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action, label: {
            primaryLabel(title)
        })
        .buttonStyle(OnboardingPrimaryButtonStyle())
    }

    private func secondaryTextLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .appFont(.body)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
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
                    .appFont(.body)
            }
        }
        .frame(maxWidth: 310)
        .padding(.vertical, layoutMode.buttonVerticalPadding)
    }

    private func routeToSignIn() {
        viewModel.routeToSignIn = true
    }

    private func startOnboarding() {
        viewModel.advance(from: .welcome)
    }

    private func createAccount() {
        Task { await viewModel.createAccount() }
    }

    private func saveProfile() {
        Task { await viewModel.saveProfile() }
    }

    private func continueFromChooseProvider() {
        viewModel.advance(from: .chooseProvider)
    }

    private func skipProviderSetup() {
        Task { await viewModel.skipProviderSetup() }
    }

    private func validateAndSaveApiKey() {
        Task { await viewModel.validateAndSaveApiKey() }
    }

    private func continueOrEnableLocation() {
        if viewModel.isLocationPermissionResolved && viewModel.locationPermissionState == .granted {
            viewModel.advance(from: .locationPermission)
        } else {
            Task { await viewModel.enableLocationPermission() }
        }
    }

    private func skipLocationPermission() {
        Task { await viewModel.skipLocationPermission() }
    }

    private func continueOrEnableNotifications() {
        if viewModel.isNotificationsPermissionResolved && viewModel.notificationsPermissionState == .granted {
            viewModel.advance(from: .notificationsPermission)
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
            onComplete()
        }
    }
}
