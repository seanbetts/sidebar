import SwiftUI

/// Step 1 of onboarding with logo, product framing, and auth routing.
struct WelcomeStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    private let animationSize: CGFloat = LoadingIndicatorSize.hero * 0.7

    var body: some View {
        OnboardingStepScaffold {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: DesignTokens.Spacing.xxl)

                LoadingIndicatorView(size: animationSize, variant: .hero)
                    .frame(width: animationSize, height: animationSize)
                    .padding(.bottom, DesignTokens.Spacing.xl)

                Text("sideBar")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .padding(.bottom, DesignTokens.Spacing.sm)

                Text("The AI assistant that actually knows you. Everything you need in one place, endlessly extensible with skills.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 300)

                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
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
    private let reservesSecondarySpace: Bool
    @ViewBuilder private let primary: Primary
    @ViewBuilder private let secondary: Secondary

    init(
        reservesSecondarySpace: Bool = false,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.reservesSecondarySpace = reservesSecondarySpace
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
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
    let totalSteps: Int
    let currentStep: Int
    @ViewBuilder private let content: Content

    init(
        totalSteps: Int,
        currentStep: Int,
        @ViewBuilder content: () -> Content
    ) {
        self.totalSteps = totalSteps
        self.currentStep = currentStep
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content

            OnboardingProgressDots(totalSteps: totalSteps, currentStep: currentStep)
                .padding(.top, DesignTokens.Spacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.bottom, DesignTokens.Spacing.xl)
    }
}
