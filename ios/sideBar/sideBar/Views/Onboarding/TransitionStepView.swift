import SwiftUI

/// Final onboarding step before entering the signed-in experience.
struct TransitionStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let dismiss: DismissAction
    let layoutMode: OnboardingLayoutMode

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing * 1.5)

                ZStack {
                    Circle()
                        .fill(DesignTokens.Colors.surface)
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, layoutMode.linkSpacing)

                Text("You're All Set")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text("I'm connected and ready to go.\nLet me show you around.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }
}
