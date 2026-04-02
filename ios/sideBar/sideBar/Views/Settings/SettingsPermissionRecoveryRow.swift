import SwiftUI

struct SettingsPermissionRecoveryRow: View {
    let item: OnboardingPermissionRecoveryItem
    let onEnable: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                label
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text(item.actionTitle)
                    .appFont(.captionSemibold)
                    .foregroundStyle(DesignTokens.Colors.actionPrimary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityHint(item.opensSystemSettings ? "Opens system settings." : "Requests permission.")
    }

    private func action() {
        if item.opensSystemSettings {
            onOpenSettings()
        } else {
            onEnable()
        }
    }

    private var label: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: item.systemImage)
                .appFont(.bodySemibold)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(item.title)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                Text(item.message)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
