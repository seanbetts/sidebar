import Combine
import sideBarShared
import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

// MARK: - LoginView
public struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStorageKeys.biometricUnlockEnabled) private var biometricUnlockEnabled = false
    @AppStorage(AppStorageKeys.lastSignInEmail) private var lastSignInEmail = ""

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSigningIn: Bool = false
    @State private var isOfflineUnlocking: Bool = false
    @State private var showSuccess: Bool = false
    @State private var lockoutSecondsRemaining: Int?
    @FocusState private var focusedField: Field?
    private let lockoutTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let onStartOnboarding: () -> Void
    private let shouldAutofocusEmail: Bool

    private enum Field {
        case email
        case password
    }
    public init(
        shouldAutofocusEmail: Bool = true,
        onStartOnboarding: @escaping () -> Void = {}
    ) {
        self.shouldAutofocusEmail = shouldAutofocusEmail
        self.onStartOnboarding = onStartOnboarding
    }

    public var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedField = nil
                }
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
                onboardingEntryView
            }
            .frame(maxWidth: 420)
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if showSuccess {
                ZStack {
                    DesignTokens.Colors.background.opacity(0.9)
                    SuccessCheckBadge(size: 120, symbolSize: 54)
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
            email = LoginEmailPrefill.initialEmail(currentEmail: email, storedEmail: lastSignInEmail)
            updateLockoutState()
        }
        .task(id: shouldAutofocusEmail) {
            guard shouldAutofocusEmail else {
                focusedField = nil
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, focusedField == nil else { return }
            focusedField = .email
        }
        .onReceive(lockoutTimer) { _ in
            updateLockoutState()
        }
        .onChange(of: environment.isNetworkAvailable) { _, isAvailable in
            if isAvailable, errorMessage == AuthAdapterError.networkUnavailable.errorDescription {
                errorMessage = nil
            }
        }
    }
    private var headerView: some View {
        VStack(spacing: 12) {
            LoadingIndicatorView(size: 64, variant: .hero)
            Text("sideBar")
                .appFont(.title2Semibold)
            VStack(spacing: 4) {
                Text("The AI assisstant that actually knows you")
            }
            .appFont(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignTokens.Spacing.sm)
        }
    }

    private var emailFieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Email", text: $email)
                .textContentType(LoginCredentialAutofillHints.email)
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
                if isValidEmail {
                    SuccessCheckBadge(size: 18, symbolSize: 10)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.error)
                        .appFont(.callout)
                }
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
                textContentType: LoginCredentialAutofillHints.password,
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
        if !environment.isNetworkAvailable {
            offlineNoticeView
        }
        if isLockedOut, let seconds = lockoutSecondsRemaining {
            HStack {
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DesignTokens.Colors.error)
                    Text("Too many failed attempts")
                        .foregroundStyle(DesignTokens.Colors.error)
                        .appFont(.callout)
                    Text("Try again in \(formatLockoutTime(seconds)).")
                        .foregroundStyle(.secondary)
                        .appFont(.caption)
                }
                .multilineTextAlignment(.center)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.errorBackground)
            .cornerRadius(DesignTokens.Radius.xsPlus)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Locked out")
            .accessibilityValue("Try again in \(formatLockoutTime(seconds))")
        } else if let errorMessage, shouldShowErrorMessage {
            HStack {
                VStack(alignment: .center, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.error)
                    Text(errorMessage)
                        .foregroundStyle(DesignTokens.Colors.error)
                        .appFont(.callout)
                    Text("Double-check your credentials and connection, then try again.")
                        .foregroundStyle(.secondary)
                        .appFont(.caption)
                }
                .multilineTextAlignment(.center)
            }
            .padding(DesignTokens.Spacing.sm)
            .background(DesignTokens.Colors.errorBackground)
            .cornerRadius(DesignTokens.Radius.xsPlus)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Error")
            .accessibilityValue(errorMessage)
            .accessibilityHint("Double-check your credentials and connection, then try again.")
        }
        if shouldShowOfflineUnlock {
            offlineUnlockView
        }
    }

    private var offlineNoticeView: some View {
        HStack {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(DesignTokens.Colors.error)
                Text("You're offline.")
                    .foregroundStyle(DesignTokens.Colors.error)
                    .appFont(.callout)
                Text("Sign in requires a connection.")
                    .foregroundStyle(.secondary)
                    .appFont(.caption)
            }
            .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .cornerRadius(DesignTokens.Radius.xsPlus)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Offline")
        .accessibilityValue("Sign in requires a connection.")
    }

    private func formatLockoutTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", secs))"
        }
        return "\(secs) seconds"
    }

    private var shouldShowOfflineUnlock: Bool {
        guard !environment.isNetworkAvailable else { return false }
        return environment.container.offlineAccessRestorer?.canRestoreOfflineSession == true
    }

    private var shouldShowErrorMessage: Bool {
        if environment.isOffline,
           errorMessage == AuthAdapterError.networkUnavailable.errorDescription {
            return false
        }
        return true
    }

    private var offlineUnlockTitle: String {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        default:
            return "Unlock Offline"
        }
        #else
        return "Unlock Offline"
        #endif
    }

    private var offlineUnlockView: some View {
        VStack(spacing: 10) {
            Text("You're offline.")
                .appFont(.callout)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text("Continue using your cached session.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { _ = await attemptOfflineUnlock() }
            } label: {
                if isOfflineUnlocking {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(offlineUnlockTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DesignTokens.Colors.actionPrimary)
            .disabled(isOfflineUnlocking)
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .cornerRadius(DesignTokens.Radius.xsPlus)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func authenticateForOfflineUnlock() async -> Bool {
        #if canImport(LocalAuthentication)
        await withCheckedContinuation { continuation in
            let context = LAContext()
            var authError: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                continuation.resume(returning: false)
                return
            }
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock sideBar to continue."
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
        #else
        return false
        #endif
    }

    private var signInButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            LoginPrimaryActionLabel(isLoading: isSigningIn)
        }
        .buttonStyle(LoginPrimaryActionButtonStyle())
        .keyboardShortcut(.defaultAction)
        .disabled(isSignInDisabled)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder
    private var onboardingEntryView: some View {
        if OnboardingPresentation.shouldAllowManualStart(authState: environment.authState) {
            LoginManualSignUpPrompt(action: onStartOnboarding)
        }
    }

    private var isSignInDisabled: Bool {
        isSigningIn || email.isEmpty || password.isEmpty || isLockedOut || !environment.isNetworkAvailable
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

private extension LoginView {
    func updateLockoutState() {
        lockoutSecondsRemaining = environment.container.signInRateLimiter?.lockoutRemainingSeconds
    }

    var isLockedOut: Bool {
        lockoutSecondsRemaining != nil && lockoutSecondsRemaining! > 0
    }

    func signIn() async {
        errorMessage = nil
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let trimmedEmail = email.trimmed
            if trimmedEmail != email {
                email = trimmedEmail
            }
            if !environment.isNetworkAvailable {
                if await attemptOfflineUnlock() {
                    return
                }
                throw AuthAdapterError.networkUnavailable
            }
            try await environment.container.authSession.signIn(email: trimmedEmail, password: password)
            lastSignInEmail = trimmedEmail
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
                errorMessage = ErrorMapping.message(for: error)
            }
            #if os(iOS)
            triggerHaptic(.error)
            #endif
        }
    }

    func attemptOfflineUnlock() async -> Bool {
        guard let offlineAccessRestorer = environment.container.offlineAccessRestorer,
              offlineAccessRestorer.canRestoreOfflineSession else {
            return false
        }
        isOfflineUnlocking = true
        defer { isOfflineUnlocking = false }
        if biometricUnlockEnabled {
            let authenticated = await authenticateForOfflineUnlock()
            guard authenticated else {
                errorMessage = "Offline unlock failed."
                return false
            }
        }
        if offlineAccessRestorer.restoreOfflineSession() {
            environment.refreshAuthState()
            return true
        }
        errorMessage = "Offline unlock failed."
        return false
    }
}
