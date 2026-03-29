import SwiftUI

/// Step 1 of onboarding with logo, product framing, and auth routing.
struct WelcomeStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let layoutMode: OnboardingLayoutMode
    let bottomContentInset: CGFloat
    private let animationSize: CGFloat = LoadingIndicatorSize.hero * 0.7

    var body: some View {
        OnboardingStepScaffold(layoutMode: layoutMode, bottomContentInset: bottomContentInset) {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: layoutMode.topSpacing)

                LoadingIndicatorView(size: animationSize, variant: .hero)
                    .frame(width: animationSize, height: animationSize)
                    .padding(.bottom, layoutMode.subtitleBottomSpacing)

                Text("sideBar")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, layoutMode.iconBottomSpacing)

                Text("The AI assistant that actually knows you. Everything you need in one place, endlessly extensible with skills.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 300)

                Spacer()
            }
            .padding(.horizontal, layoutMode.horizontalPadding)
        }
    }
}

/// Monochrome primary button used across onboarding.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DesignTokens.Colors.background)
            .background(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

/// Shared onboarding footer that keeps primary CTAs aligned across steps.
struct OnboardingActionArea<Primary: View, Secondary: View>: View {
    let layoutMode: OnboardingLayoutMode
    private let reservesSecondarySpace: Bool
    @ViewBuilder private let primary: Primary
    @ViewBuilder private let secondary: Secondary

    init(
        layoutMode: OnboardingLayoutMode,
        reservesSecondarySpace: Bool = false,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.layoutMode = layoutMode
        self.reservesSecondarySpace = reservesSecondarySpace
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(spacing: layoutMode.footerSpacing) {
            primary

            secondarySlot
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var secondarySlot: some View {
        if reservesSecondarySpace {
            secondary
                .frame(minHeight: 22, alignment: .top)
        } else {
            secondary
        }
    }
}

/// Shared onboarding bottom area matching the HTML mockup structure: actions first, progress below.
struct OnboardingBottomArea<Content: View>: View {
    let layoutMode: OnboardingLayoutMode
    let totalSteps: Int
    let currentStep: Int
    @ViewBuilder private let content: Content

    init(
        layoutMode: OnboardingLayoutMode,
        totalSteps: Int,
        currentStep: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.layoutMode = layoutMode
        self.totalSteps = totalSteps
        self.currentStep = currentStep
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content

            OnboardingProgressDots(totalSteps: totalSteps, currentStep: currentStep)
                .padding(.top, layoutMode.progressTopPadding)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layoutMode.horizontalPadding)
        .padding(.bottom, layoutMode.bottomPadding)
    }
}
