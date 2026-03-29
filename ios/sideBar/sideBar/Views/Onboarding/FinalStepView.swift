import SwiftUI

/// Final onboarding step before entering the signed-in experience.
struct FinalStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
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

                Text(viewModel.transitionTitle)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("onboarding.finalStep.title")
                    .padding(.bottom, layoutMode.titleBottomSpacing)

                Text(viewModel.transitionSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !viewModel.transitionHighlights.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        ForEach(viewModel.transitionHighlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .padding(.top, 6)
                                Text(highlight)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: 310, alignment: .leading)
                    .padding(.top, layoutMode.sectionSpacing)
                }

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }
}
