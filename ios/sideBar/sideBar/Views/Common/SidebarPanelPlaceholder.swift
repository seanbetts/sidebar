import SwiftUI
import sideBarShared

public struct SidebarPanelPlaceholder: View {
    public enum Style {
        case standard
        case error
    }

    public let title: String
    public let subtitle: String?
    public let actionTitle: String?
    public let action: (() -> Void)?
    public let style: Style
    public let icon: AppIcon?

    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        style: Style = .standard,
        icon: AppIcon? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.style = style
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if let icon = resolvedIcon {
                    Image(appIcon: icon)
                        .appFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .appFont(.subheading)
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .appFont(.subheading)
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(style == .error ? DesignTokens.Spacing.sm : 0)
            .background(style == .error ? DesignTokens.Colors.errorBackground : .clear)
            .overlay {
                if style == .error {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                        .stroke(DesignTokens.Colors.errorBorder, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous))
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignTokens.Spacing.md)
    }

    private var resolvedIcon: AppIcon? {
        if let icon {
            return icon
        }
        return style == .error ? AppIcon.State.warningFilled : nil
    }

    private var iconColor: Color {
        style == .error ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary
    }

    private var titleColor: Color {
        style == .error ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary
    }

    private var subtitleColor: Color {
        style == .error ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary
    }
}
