import SwiftUI

/// Step 2 of onboarding for account creation.
struct CreateAccountStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        OnboardingStepScaffold {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: DesignTokens.Spacing.xxl)

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.primary)
                    .padding(.bottom, DesignTokens.Spacing.md)

                Text("Let's Set You Up")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, DesignTokens.Spacing.xs)

                Text("Enter your email and choose a password to create your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, DesignTokens.Spacing.xl)

                VStack(spacing: DesignTokens.Spacing.md) {
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
                        .padding(.top, DesignTokens.Spacing.sm)
                }

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
        .onAppear {
            focusedField = .email
        }
    }
}
