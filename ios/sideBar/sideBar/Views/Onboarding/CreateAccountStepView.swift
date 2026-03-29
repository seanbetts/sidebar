import SwiftUI

/// Step 2 of onboarding for account creation.
struct CreateAccountStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text("Let's Set You Up")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text("Enter your email and choose a password to create your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, layoutMode.subtitleBottomSpacing)

                VStack(spacing: layoutMode.sectionSpacing) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("EMAIL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        TextField("Enter your email", text: $viewModel.email)
                            .textContentType(LoginCredentialAutofillHints.email)
#if canImport(UIKit)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
#endif
                            .autocorrectionDisabled()
                            .padding(DesignTokens.Spacing.sm)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: DesignTokens.Radius.sm,
                                    style: .continuous
                                )
                                .fill(DesignTokens.Colors.surface)
                            }
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit {
                                focusedField = .password
                            }
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text("PASSWORD")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        SecureField("Choose a password", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .padding(DesignTokens.Spacing.sm)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: DesignTokens.Radius.sm,
                                    style: .continuous
                                )
                                .fill(DesignTokens.Colors.surface)
                            }
                            .focused($focusedField, equals: .password)
                            .submitLabel(.continue)
                            .onSubmit {
                                guard viewModel.isCreateAccountValid && !viewModel.isLoading else { return }
                                Task { await viewModel.createAccount() }
                            }

                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index < viewModel.passwordStrength ? Color.primary : DesignTokens.Colors.muted)
                                    .frame(height: 4)
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.xxs)
                    }
                }
                .frame(maxWidth: 310)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .padding(.top, layoutMode.sectionSpacing)
                }

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
        .onboardingDeferredAutofocus($focusedField, equals: .email)
    }
}
