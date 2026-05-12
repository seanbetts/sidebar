import SwiftUI
import sideBarShared

struct EmptyStateView: View {
    let title: String
    let subtitle: String?
    let icon: AppIcon?

    var systemImage: String? {
        icon?.rawValue
    }

    init(title: String, subtitle: String? = nil, icon: AppIcon? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    init(title: String, subtitle: String? = nil, systemImage: String?) {
        self.init(title: title, subtitle: subtitle, icon: systemImage.map(AppIcon.init(rawValue:)))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if let icon {
                Image(appIcon: icon)
                    .appScaledFont(size: DesignTokens.Icon.lg, weight: .medium)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: DesignTokens.Icon.xxl, height: DesignTokens.Icon.xxl)
                    .background(
                        Circle()
                            .fill(DesignTokens.Colors.muted.opacity(0.55))
                    )
                    .accessibilityHidden(true)
            }
            Text(title)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .appFont(.subheading)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}
