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
    @State private var passwordResetNotice: String?
    @State private var passwordResetNoticeDetail: String?
    @State private var isSigningIn: Bool = false
    @State private var isRequestingPasswordReset: Bool = false
    @State private var isOfflineUnlocking: Bool = false
    @State private var showSuccess: Bool = false
    @State private var lockoutSecondsRemaining: Int?
    @FocusState private var focusedField: Field?
    private let lockoutTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let initialPasswordResetNotice: String?
    private let initialPasswordResetNoticeDetail: String?
    private let onConsumePasswordResetNotice: (() -> Void)?
    private let onStartOnboarding: () -> Void
    private let shouldAutofocusEmail: Bool

    private enum Field {
        case email
        case password
    }
    public init(
        initialPasswordResetNotice: String? = nil,
        initialPasswordResetNoticeDetail: String? = nil,
        onConsumePasswordResetNotice: (() -> Void)? = nil,
        shouldAutofocusEmail: Bool = true,
        onStartOnboarding: @escaping () -> Void = {}
    ) {
        self.initialPasswordResetNotice = initialPasswordResetNotice
        self.initialPasswordResetNoticeDetail = initialPasswordResetNoticeDetail
        self.onConsumePasswordResetNotice = onConsumePasswordResetNotice
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
                            passwordResetActionRow
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
            passwordResetNotice = nil
            passwordResetNoticeDetail = nil
        }
        .onChange(of: password) { _, _ in
            errorMessage = nil
            passwordResetNotice = nil
            passwordResetNoticeDetail = nil
        }
        .onAppear {
            email = LoginEmailPrefill.initialEmail(currentEmail: email, storedEmail: lastSignInEmail)
            if passwordResetNotice == nil, let initialPasswordResetNotice {
                passwordResetNotice = initialPasswordResetNotice
                passwordResetNoticeDetail = initialPasswordResetNoticeDetail
                onConsumePasswordResetNotice?()
            }
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
                .appFont(.titleLg)
            VStack(spacing: 4) {
                Text(MarketingCopy.tagline)
            }
            .appFont(.subheading)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignTokens.Spacing.sm)
        }
    }
    private var emailFieldRow: some View {
        LoginFieldRow(leadingSystemName: "envelope") {
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
        } trailing: {
            if !email.isEmpty {
                if isValidEmail {
                    SuccessCheckBadge(
                        size: LoginFieldChromeMetrics.statusBadgeSize,
                        symbolSize: LoginFieldChromeMetrics.statusBadgeSymbolSize
                    )
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Colors.error)
                        .font(.system(size: LoginFieldChromeMetrics.trailingSymbolPointSize))
                }
            }
            if !email.isEmpty {
                Button {
                    email = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: LoginFieldChromeMetrics.trailingSymbolPointSize))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilitySortPriority(3)
    }
    private var passwordFieldRow: some View {
        FormField(leadingSystemName: "lock") {
            FormFieldSecureInput(
                title: "Password",
                text: $password,
                focus: $focusedField,
                field: .password,
                textContentType: LoginCredentialAutofillHints.password,
                submitLabel: .go,
                onSubmit: { Task { await signIn() } }
            )
        } trailing: {
            if !password.isEmpty {
                Button {
                    password = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: LoginFieldChromeMetrics.trailingSymbolPointSize))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilitySortPriority(2)
    }
    @ViewBuilder
    private var errorView: some View {
        if let passwordResetNotice {
            LoginPasswordResetNoticeView(
                message: passwordResetNotice,
                detail: passwordResetNoticeDetail
            )
        }
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
                        .appFont(.body)
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
                        .appFont(.body)
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
        LoginOfflineNoticeView()
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
        LoginOfflineUnlockView(
            title: offlineUnlockTitle,
            isLoading: isOfflineUnlocking,
            action: { Task { _ = await attemptOfflineUnlock() } }
        )
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
    private var passwordResetActionRow: some View {
        LoginPasswordResetActionRow(
            isRequesting: isRequestingPasswordReset,
            color: passwordResetActionColor,
            action: { Task { await requestPasswordReset() } }
        )
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
    private var isValidEmail: Bool {
        isValidEmail(email)
    }
    private var passwordResetActionColor: Color {
        isRequestingPasswordReset ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.actionPrimary
    }
    private func isValidEmail(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmed
        guard !trimmed.isEmpty else { return false }
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: trimmed)
    }
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
        passwordResetNotice = nil
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
            Haptics.notification(.success)
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
            Haptics.notification(.error)
        }
    }
    func requestPasswordReset() async {
        errorMessage = nil
        passwordResetNotice = nil
        passwordResetNoticeDetail = nil

        let trimmedEmail = email.trimmed
        if trimmedEmail != email {
            email = trimmedEmail
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Enter your email to reset your password."
            return
        }
        guard environment.isNetworkAvailable else {
            errorMessage = "Password reset requires a connection."
            return
        }
        isRequestingPasswordReset = true
        defer { isRequestingPasswordReset = false }
        do {
            try await environment.container.passwordResetAPI.requestPasswordReset(email: trimmedEmail)
            passwordResetNotice = "Check your email for a reset link."
            passwordResetNoticeDetail = nil
        } catch {
            errorMessage = PasswordResetErrorPresentation.message(for: error)
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
