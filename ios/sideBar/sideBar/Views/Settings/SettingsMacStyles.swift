import SwiftUI

func settingsMacSidebarWidth() -> CGFloat {
    232
}

func settingsMacRowLabelWidth() -> CGFloat {
    160
}

func settingsMacSectionIntroSpacing() -> CGFloat {
    6
}

func settingsMacWeatherPickerStyle() -> some PickerStyle {
    SegmentedPickerStyle()
}

enum SettingsMacStatusTone {
    case info
    case error
}

struct SettingsMacSectionIntro: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: settingsMacSectionIntroSpacing()) {
            Text(title)
                .appFont(.headline)
            Text(message)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }
}

struct SettingsMacFieldRow<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Text(label)
                .appFont(.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: settingsMacRowLabelWidth(), alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}

struct SettingsMacHeroButtonRow<Leading: View>: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    private let leading: Leading

    init(
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                leading

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxsPlus) {
                    Text(title)
                        .appFont(.subheadlineSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                Image(systemName: "chevron.right")
                    .appFont(.captionSemibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(DesignTokens.Colors.settingsFormBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(DesignTokens.Colors.border.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMacStatusBanner: View {
    let message: String
    let tone: SettingsMacStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(iconColor)
                .padding(.top, 2)

            Text(message)
                .appFont(.caption)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconColor: Color {
        switch tone {
        case .info:
            return DesignTokens.Colors.textSecondary
        case .error:
            return DesignTokens.Colors.error
        }
    }

    private var textColor: Color {
        switch tone {
        case .info:
            return DesignTokens.Colors.textSecondary
        case .error:
            return DesignTokens.Colors.error
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .info:
            return DesignTokens.Colors.muted.opacity(0.5)
        case .error:
            return DesignTokens.Colors.errorSurface
        }
    }

    private var borderColor: Color {
        switch tone {
        case .info:
            return DesignTokens.Colors.border.opacity(0.45)
        case .error:
            return DesignTokens.Colors.errorBorder
        }
    }
}

struct SettingsMacActionSection<Content: View>: View {
    let title: String
    let message: String
    private let content: Content

    init(
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.message = message
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            SettingsMacSectionIntro(title: title, message: message)
            content
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.settingsFormBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }
}

struct SettingsMacPanelCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            content
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.settingsFormBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }
}

struct SettingsMacSkillRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: (() -> Void)?
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(systemName: systemImage)
                .appFont(.subheadlineSemibold)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxsPlus) {
                Text(title)
                    .appFont(.subheadlineSemibold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            trailing
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.settingsFormBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(DesignTokens.Colors.border.opacity(0.45), lineWidth: 1)
        )
    }
}
