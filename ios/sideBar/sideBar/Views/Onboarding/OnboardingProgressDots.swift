import SwiftUI

/// Progress indicator showing completed, active, and upcoming onboarding steps.
struct OnboardingProgressDots: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index == currentStep {
            return .primary
        }
        if index < currentStep {
            return .secondary
        }
        return DesignTokens.Colors.muted
    }
}
