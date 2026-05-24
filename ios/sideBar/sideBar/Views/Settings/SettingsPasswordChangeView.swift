import SwiftUI
import sideBarShared

struct SettingsPasswordChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var environment: AppEnvironment

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case newPassword
        case confirmPassword
    }

    private var passwordValidation: PasswordFormValidation {
        PasswordFormValidation(newPassword: newPassword, confirmPassword: confirmPassword)
    }

    private var passwordStrength: Int {
        passwordValidation.strengthScore
    }

    private var hasMinimumPasswordLength: Bool {
        passwordValidation.hasMinimumPasswordLength
    }

    private var passwordMismatchMessage: String? {
        passwordValidation.passwordMismatchMessage
    }

    private var canSubmit: Bool {
        passwordValidation.canSubmit(isSubmitting: isSubmitting)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Password") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text("New password")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)

                            passwordFieldRow(
                                title: "New password",
                                text: $newPassword,
                                field: .newPassword,
                                submitLabel: .next
                            ) {
                                focusedField = .confirmPassword
                            }
                        }

                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { index in
                                Capsule()
                                    .fill(index < passwordStrength ? Color.primary : DesignTokens.Colors.border.opacity(0.85))
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

                        Divider()

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Text("Confirm new password")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)

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
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("Update Password")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .buttonStyle(LoginPrimaryActionButtonStyle())
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Change Password")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: newPassword) {
            errorMessage = nil
        }
        .onChange(of: confirmPassword) {
            errorMessage = nil
        }
        .task {
            guard focusedField == nil else { return }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            focusedField = .newPassword
        }
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
        return PasswordStrengthRules.guidanceMessage
    }

    private func passwordFieldRow(
        title: String,
        text: Binding<String>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        FormField(leadingIcon: AppIcon.Auth.password) {
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

        guard passwordValidation.canSubmit(isSubmitting: isSubmitting) else {
            if !hasMinimumPasswordLength {
                errorMessage = "Password must be at least 8 characters."
            } else if let passwordMismatchMessage {
                errorMessage = passwordMismatchMessage
            }
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await environment.completeSettingsPasswordChange(newPassword: newPassword)
            dismiss()
        } catch let authError as AuthAdapterError {
            errorMessage = authError.errorDescription
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }
}
