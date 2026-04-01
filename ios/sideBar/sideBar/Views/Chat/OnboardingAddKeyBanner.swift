import SwiftUI

struct OnboardingAddKeyBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: DesignTokens.Icon.md, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(width: DesignTokens.Size.touchTarget, height: DesignTokens.Size.touchTarget)
                .background(
                    DesignTokens.Colors.muted.opacity(0.65),
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.Radius.sm,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Add an API key to start using the assistant")
                    .appFont(.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text("Notes, tasks, websites, and files still work while chat stays unavailable.")
                    .appFont(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}
