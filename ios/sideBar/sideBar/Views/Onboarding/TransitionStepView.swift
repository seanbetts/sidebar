import SwiftUI

/// Final onboarding step before entering the signed-in experience.
struct TransitionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: DesignTokens.Spacing.xxl * 2)

            ZStack {
                Circle()
                    .fill(DesignTokens.Colors.surface)
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, DesignTokens.Spacing.lg)

            Text("You're All Set")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .padding(.bottom, DesignTokens.Spacing.xs)

            Text("I'm connected and ready to go.\nLet me show you around.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: {
                Task {
                    await viewModel.completeOnboarding()
                    dismiss()
                }
            }, label: {
                Text("Meet sideBar")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 310)
                    .padding(.vertical, DesignTokens.Spacing.md)
            })
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
    }
}
