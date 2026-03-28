import SwiftUI

/// Step 3 of onboarding for OTP verification.
struct VerifyEmailStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var otpDigits = Array(repeating: "", count: 6)
    @FocusState private var focusedIndex: Int?
    @State private var resendCooldown = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: DesignTokens.Spacing.xxl)

            Image(systemName: "envelope.badge")
                .font(.system(size: 48))
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.md)

            Text("Check Your Inbox")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            Text("I sent a verification code to")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            Text(viewModel.email)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.xl)

            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: $otpDigits[index])
#if canImport(UIKit)
                        .keyboardType(.numberPad)
#endif
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 44, height: 52)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                                .stroke(focusedIndex == index ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .focused($focusedIndex, equals: index)
                        .onChange(of: otpDigits[index]) { _, newValue in
                            handleDigitChange(at: index, value: newValue)
                        }
                }
            }
            .padding(.bottom, DesignTokens.Spacing.xl)

            if viewModel.isLoading {
                ProgressView()
                    .padding(.bottom, DesignTokens.Spacing.md)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .padding(.bottom, DesignTokens.Spacing.md)
            }

            Button(resendCooldown > 0 ? "Resend code (\(resendCooldown)s)" : "Resend code") {
                resendCode()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .disabled(resendCooldown > 0)
            .padding(.bottom, DesignTokens.Spacing.sm)

            Button("Wrong email? Go back") {
                viewModel.currentStep = .createAccount
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .onAppear {
            focusedIndex = 0
        }
    }

    private func handleDigitChange(at index: Int, value: String) {
        let digitsOnly = value.filter(\.isNumber)
        if digitsOnly != value {
            otpDigits[index] = digitsOnly
            return
        }

        if digitsOnly.count > 1 {
            let pastedDigits = Array(digitsOnly.prefix(6))
            for digitIndex in otpDigits.indices {
                otpDigits[digitIndex] = digitIndex < pastedDigits.count ? String(pastedDigits[digitIndex]) : ""
            }
            if pastedDigits.count == otpDigits.count {
                submitCode()
            } else {
                focusedIndex = min(pastedDigits.count, otpDigits.count - 1)
            }
            return
        }

        if !digitsOnly.isEmpty && index < otpDigits.count - 1 {
            focusedIndex = index + 1
        } else if digitsOnly.isEmpty && index > 0 {
            focusedIndex = index - 1
        }

        if otpDigits.allSatisfy({ $0.count == 1 }) {
            submitCode()
        }
    }

    private func submitCode() {
        let code = otpDigits.joined()
        guard code.count == otpDigits.count else { return }
        Task {
            await viewModel.verifyOTP(code: code)
        }
    }

    private func resendCode() {
        resendCooldown = 60
        Task {
            if !viewModel.isTestingOnboarding {
                try? await viewModel.resendVerificationCode()
            }
            while resendCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                resendCooldown -= 1
            }
        }
    }
}
