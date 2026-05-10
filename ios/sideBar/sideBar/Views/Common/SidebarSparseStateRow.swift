import SwiftUI

public struct SidebarSparseStateRow: View {
    public let iconName: String
    public let title: String
    public let subtitle: String?

    public init(iconName: String, title: String, subtitle: String? = nil) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        SelectableRow(isSelected: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Image(systemName: iconName)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(title)
                    .appFont(.subheading)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.subheading)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
