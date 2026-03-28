import SwiftUI

/// Step 1 of onboarding with logo, product framing, and auth routing.
struct WelcomeStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: DesignTokens.Spacing.xxl)

            LoadingIndicatorView(size: LoadingIndicatorSize.hero, variant: .hero)
                .frame(width: LoadingIndicatorSize.hero, height: LoadingIndicatorSize.hero)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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

            VStack(spacing: DesignTokens.Spacing.md) {
                Button(action: { viewModel.advance() }, label: {
                    Text("Get Started")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 310)
                        .padding(.vertical, DesignTokens.Spacing.md)
                })
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button("Already have an account? Sign In", action: {
                    viewModel.routeToSignIn = true
                })
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.xxl)
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
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
