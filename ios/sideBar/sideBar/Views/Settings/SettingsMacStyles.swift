import SwiftUI
import sideBarShared

func settingsMacSidebarWidth() -> CGFloat {
    232
}

func settingsMacRowLabelWidth() -> CGFloat {
    FormFieldLayoutMetrics.settingsMacLabelWidth
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
                .appFont(.subheading)
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
        FormField(label) {
            content
        }
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
                        .appFont(.subheading)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                Image(systemName: "chevron.right")
                    .appFont(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .glassChrome(Self.chromeKind)
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

    static var chromeKind: GlassChrome.Kind {
        .card
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
        .glassChrome(Self.chromeKind)
    }

    static var chromeKind: GlassChrome.Kind {
        .card
    }
}

struct SettingsMacSkillRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String?
    let icon: AppIcon?
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
        self.icon = nil
        self.action = action
        self.trailing = trailing()
    }

    init(
        title: String,
        subtitle: String,
        icon: AppIcon,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = nil
        self.icon = icon
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
            rowIcon
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxsPlus) {
                Text(title)
                    .appFont(.subheading)
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

    @ViewBuilder
    private var rowIcon: some View {
        if let icon {
            Image(appIcon: icon)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        } else if let systemImage {
            Image(systemName: systemImage)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}
