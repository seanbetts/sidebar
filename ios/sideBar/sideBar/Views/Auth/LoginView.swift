import Combine
import SwiftUI

// MARK: - LoginView

public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false
    @State private var showSuccess: Bool = false
    @State private var lockoutSecondsRemaining: Int?
    @FocusState private var focusedField: Field?

    private let lockoutTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                }
                .groupBoxStyle(LoginGroupBoxStyle())
            }
            .frame(maxWidth: 420)
            .padding(DesignTokens.Spacing.xl)
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
                        .font(DesignTokens.Typography.logo)
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                if focusedField == nil {
                    focusedField = .email
                }
            }
            updateLockoutState()
        }
        .onReceive(lockoutTimer) { _ in
            updateLockoutState()
        }
    }

    private func updateLockoutState() {
        if let authAdapter = environment.container.authSession as? SupabaseAuthAdapter {
            lockoutSecondsRemaining = authAdapter.lockoutRemainingSeconds
        }
    }

    private var isLockedOut: Bool {
        lockoutSecondsRemaining != nil && lockoutSecondsRemaining! > 0
    }

    private func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let trimmedEmail = email.trimmed
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

    private var headerView: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            Text("sideBar")
                .font(DesignTokens.Typography.title2Semibold)
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
                .onSubmit {
                    focusedField = .password
                }
            if !email.isEmpty {
                Image(systemName: isValidEmail ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isValidEmail ? .green : .orange)
                    .font(.callout)
            }
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
        }
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .padding(.horizontal, DesignTokens.Spacing.sm)
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
                focus: $focusedField,
                field: .password,
                textContentType: .password,
                submitLabel: .go,
                onSubmit: { Task { await signIn() } }
            )
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
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(fieldBackground)
        .overlay(fieldBorder)
        .accessibilitySortPriority(2)
    }

    @ViewBuilder
    private var errorView: some View {
        if isLockedOut, let seconds = lockoutSecondsRemaining {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(DesignTokens.Colors.error)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Too many failed attempts")
                        .foregroundStyle(DesignTokens.Colors.error)
                        .font(.callout)
                    Text("Try again in \(formatLockoutTime(seconds)).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.errorBackground)
            .cornerRadius(DesignTokens.Radius.xsPlus)
            .accessibilityLabel("Locked out")
            .accessibilityValue("Try again in \(formatLockoutTime(seconds))")
        } else if let errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.error)
                VStack(alignment: .leading, spacing: 4) {
                    Text(errorMessage)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .font(.callout)
                    Text("Double-check your credentials and connection, then try again.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.errorBackground)
            .cornerRadius(DesignTokens.Radius.xsPlus)
            .accessibilityLabel("Error")
            .accessibilityValue(errorMessage)
            .accessibilityHint("Double-check your credentials and connection, then try again.")
        }
    }

    private func formatLockoutTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", secs))"
        }
        return "\(secs) seconds"
    }

    private var signInButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            ZStack {
                // Hidden content to maintain consistent size
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Signing in...")
                }
                .opacity(0)
                // Visible content
                if isSigningIn {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text("Signing in...")
                    }
                } else {
                    Text("Sign In")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.white)
        .foregroundStyle(.black)
        .disabled(isSigningIn || email.isEmpty || password.isEmpty || isLockedOut)
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
        let trimmed = email.trimmed
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
