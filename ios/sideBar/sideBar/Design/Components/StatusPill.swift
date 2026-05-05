import SwiftUI

enum StatusPillTone: String, CaseIterable {
    case neutral
    case success
    case warning
    case error
    case loading

    var foregroundColor: Color {
        switch self {
        case .neutral:
            return DesignTokens.Colors.textPrimary
        case .success:
            return DesignTokens.Colors.success
        case .warning:
            return DesignTokens.Colors.warning
        case .error:
            return DesignTokens.Colors.error
        case .loading:
            return DesignTokens.Colors.textSecondary
        }
    }

    var borderColor: Color {
        switch self {
        case .neutral, .loading:
            return DesignTokens.Colors.border
        case .success:
            return DesignTokens.Colors.successBorder
        case .warning:
            return DesignTokens.Colors.warningBorder
        case .error:
            return DesignTokens.Colors.errorBorder
        }
    }

    var iconName: String? {
        switch self {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .loading:
            return nil
        }
    }
}

enum StatusPillStyle {
    case compact
    case banner

    var fontStyle: AppFontStyle {
        switch self {
        case .compact:
            return .captionSemibold
        case .banner:
            return .subheading
        }
    }

    var symbolFontStyle: AppFontStyle {
        switch self {
        case .compact:
            return .captionSemibold
        case .banner:
            return .labelMd
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact:
            return DesignTokens.Spacing.xs
        case .banner:
            return DesignTokens.Spacing.md
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .compact:
            return DesignTokens.Spacing.xxs
        case .banner:
            return DesignTokens.Spacing.xsPlus
        }
    }

    var progressControlSize: ControlSize {
        switch self {
        case .compact:
            return .small
        case .banner:
            return .regular
        }
    }
}

struct StatusPill: View {
    let title: String
    let tone: StatusPillTone
    let style: StatusPillStyle
    let action: (() -> Void)?
    let accessibilityLabel: String?

    init(
        title: String,
        tone: StatusPillTone,
        style: StatusPillStyle = .compact,
        action: (() -> Void)? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.tone = tone
        self.style = style
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    pillLabel
                }
                .buttonStyle(.plain)
            } else {
                pillLabel
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? title)
    }

    private var pillLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xxsPlus) {
            leadingAccessory

            Text(title)
                .appFont(style.fontStyle)
                .foregroundStyle(tone.foregroundColor)
                .lineLimit(2)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .glassChrome(.statusPill)
        .overlay {
            Capsule()
                .stroke(tone.borderColor, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if tone == .loading {
            ProgressView()
                .controlSize(style.progressControlSize)
                .tint(DesignTokens.Colors.textSecondary)
        } else if let iconName = tone.iconName {
            Image(systemName: iconName)
                .appFont(style.symbolFontStyle)
                .foregroundStyle(tone.foregroundColor)
        }
    }
}
