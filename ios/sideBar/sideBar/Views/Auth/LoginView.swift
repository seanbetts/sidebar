import SwiftUI

public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false
    @State private var showSuccess: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    public init() {
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 24) {
                headerView

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            emailFieldRow
                            passwordFieldRow
                        }

                        errorView

                        signInButton
                    }
                    .onSubmit(handleSubmit)
                }
                .groupBoxStyle(LoginGroupBoxStyle())
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(DesignTokens.Colors.background)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }

            if showSuccess {
                ZStack {
                    Color.green.opacity(0.9)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white)
                }
                .ignoresSafeArea()
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background(DesignTokens.Colors.background)
        .onChange(of: email) { _, _ in
            errorMessage = nil
        }
        .onChange(of: password) { _, _ in
            errorMessage = nil
        }
        .onAppear {
            focusedField = .email
        }
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEmail != email {
                email = trimmedEmail
            }
            guard !environment.isOffline else {
                throw AuthAdapterError.networkUnavailable
            }
            try await environment.container.authSession.signIn(email: trimmedEmail, password: password)
            environment.refreshAuthState()
            #if os(iOS)
            triggerHaptic(.success)
            #endif
            if reduceMotion {
                showSuccess = true
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSuccess = true
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(0.7))
                await MainActor.run {
                    showSuccess = false
                }
            }
        } catch {
            if let authError = error as? AuthAdapterError {
                errorMessage = authError.errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
            #if os(iOS)
            triggerHaptic(.error)
            #endif
        }
    }

    private func handleSubmit() {
        switch focusedField {
        case .email:
            focusedField = .password
        case .password:
            Task { await signIn() }
        case .none:
            break
        }
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            Text("sideBar")
                .font(.title2.weight(.semibold))
        }
    }

    private var emailFieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Email", text: $email)
                .textContentType(.username)
        #if canImport(UIKit)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        #endif
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
            if !email.isEmpty {
                Button {
                    email = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            if !email.isEmpty {
                Image(systemName: isValidEmail ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isValidEmail ? .green : .orange)
                    .font(.callout)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(fieldBackground)
        .overlay(fieldBorder)
        .accessibilitySortPriority(3)
    }

    private var passwordFieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            SecureFieldWithToggle(
                title: "Password",
                text: $password,
                textContentType: .password
            )
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            if !password.isEmpty {
                Button {
                    password = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(fieldBackground)
        .overlay(fieldBorder)
        .accessibilitySortPriority(2)
    }

    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                    Text("Double-check your credentials and connection, then try again.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .accessibilityLabel("Error")
            .accessibilityValue(errorMessage)
            .accessibilityHint("Double-check your credentials and connection, then try again.")
        }
    }

    private var signInButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            ZStack {
                Text(isSigningIn ? "Signing in..." : "Sign In")
                if isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(isSigningIn || email.isEmpty || password.isEmpty)
        .accessibilitySortPriority(1)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
    }

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmed)
    }

    #if os(iOS)
    private func triggerHaptic(_ style: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(style)
    }
    #endif
}

private struct LoginGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            configuration.label
            configuration.content
        }
        .cardStyle()
    }
}
