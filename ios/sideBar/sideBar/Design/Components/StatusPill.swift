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
            return DesignTokens.Colors.warning
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

struct StatusPill: View {
    let title: String
    let tone: StatusPillTone
    let action: (() -> Void)?
    let accessibilityLabel: String?

    init(
        title: String,
        tone: StatusPillTone,
        action: (() -> Void)? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.tone = tone
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
                .appFont(.captionSemibold)
                .foregroundStyle(tone.foregroundColor)
                .lineLimit(2)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
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
                .controlSize(.small)
                .tint(DesignTokens.Colors.textSecondary)
        } else if let iconName = tone.iconName {
            Image(systemName: iconName)
                .appFont(.captionSemibold)
                .foregroundStyle(tone.foregroundColor)
        }
    }
}
