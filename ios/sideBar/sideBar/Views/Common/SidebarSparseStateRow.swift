import SwiftUI
import sideBarShared

public struct SidebarSparseStateRow: View {
    public let icon: AppIcon
    public let title: String
    public let subtitle: String?

    public init(icon: AppIcon, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        SelectableRow(isSelected: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Image(appIcon: icon)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(title)
                    .appFont(.subheading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.body)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
