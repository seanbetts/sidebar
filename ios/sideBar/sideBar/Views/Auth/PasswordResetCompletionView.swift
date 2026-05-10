import SwiftUI

struct PasswordResetCompletionView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case newPassword
        case confirmPassword
    }

    private var trimmedNewPassword: String {
        newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedConfirmPassword: String {
        confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordStrength: Int {
        PasswordStrengthRules.score(for: trimmedNewPassword)
    }

    private var hasMinimumPasswordLength: Bool {
        trimmedNewPassword.count >= PasswordStrengthRules.minimumLength
    }

    private var passwordMismatchMessage: String? {
        guard !confirmPassword.isEmpty, trimmedNewPassword != trimmedConfirmPassword else {
            return nil
        }
        return "Passwords do not match."
    }

    private var canSubmit: Bool {
        !isSubmitting && hasMinimumPasswordLength && !trimmedConfirmPassword.isEmpty && passwordMismatchMessage == nil
    }

    private var inactivePasswordStrengthColor: Color {
        DesignTokens.Colors.border.opacity(0.85)
    }

    private var passwordGuidanceMessage: String {
        PasswordStrengthRules.guidanceMessage
    }

    private var passwordGuidanceColor: Color {
        if !newPassword.isEmpty && !hasMinimumPasswordLength {
            return DesignTokens.Colors.error
        }
        return DesignTokens.Colors.textSecondary
    }

    private var passwordGuidanceDisplayMessage: String {
        if !newPassword.isEmpty && !hasMinimumPasswordLength {
            return "Password must be at least 8 characters."
        }
        return passwordGuidanceMessage
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { focusedField = nil }

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    LoadingIndicatorView(size: 64, variant: .hero)
                    Text("Enter a new password")
                        .appFont(.titleLg)
                    Text("Finish resetting your password, then sign in again with the updated credentials.")
                        .appFont(.subheading)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            passwordFieldRow(
                                title: "New password",
                                text: $newPassword,
                                field: .newPassword,
                                submitLabel: .next
                            ) {
                                focusedField = .confirmPassword
                            }

                            HStack(spacing: 4) {
                                ForEach(0..<4, id: \.self) { index in
                                    Capsule()
                                        .fill(index < passwordStrength ? Color.primary : inactivePasswordStrengthColor)
                                        .frame(height: 4)
                                }
                            }
                            .padding(.top, DesignTokens.Spacing.xxs)

                            Text(passwordGuidanceDisplayMessage)
                                .appFont(.caption)
                                .foregroundStyle(passwordGuidanceColor)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                        }

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            passwordFieldRow(
                                title: "Confirm new password",
                                text: $confirmPassword,
                                field: .confirmPassword,
                                submitLabel: .go
                            ) {
                                Task { await submit() }
                            }

                            Text(passwordMismatchMessage ?? " ")
                                .appFont(.caption)
                                .foregroundStyle(DesignTokens.Colors.error)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .appFont(.caption)
                                .foregroundStyle(DesignTokens.Colors.error)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if isSubmitting {
                                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Text("Update password")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .buttonStyle(LoginPrimaryActionButtonStyle())
                        .disabled(!canSubmit)

                        Button("Back to sign in") {
                            Task { await environment.cancelPasswordRecovery() }
                        }
                        .buttonStyle(.plain)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.actionPrimary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .groupBoxStyle(LoginGroupBoxStyle())
            }
            .frame(maxWidth: 420)
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task {
            guard focusedField == nil else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            focusedField = .newPassword
        }
        .onChange(of: newPassword) {
            errorMessage = nil
        }
        .onChange(of: confirmPassword) {
            errorMessage = nil
        }
    }

    private func passwordFieldRow(
        title: String,
        text: Binding<String>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        FormField(leadingSystemName: "lock") {
            FormFieldSecureInput(
                title: title,
                text: text,
                focus: $focusedField,
                field: field,
                textContentType: .newPassword,
                submitLabel: submitLabel,
                onSubmit: onSubmit
            )
        }
    }

    private func submit() async {
        errorMessage = nil

        guard hasMinimumPasswordLength else {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        guard passwordMismatchMessage == nil else {
            errorMessage = "Passwords do not match."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await environment.completePasswordRecovery(newPassword: trimmedNewPassword)
        } catch let authError as AuthAdapterError {
            errorMessage = authError.errorDescription
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}
