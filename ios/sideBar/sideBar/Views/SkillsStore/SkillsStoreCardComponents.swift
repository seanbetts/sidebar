import SwiftUI
import sideBarShared

enum SkillsStoreCategoryIcon {
    static func appIcon(for raw: String) -> AppIcon {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized == "all" { return AppIcon.Skills.categoryAll }
        if normalized.contains("audio") || normalized.contains("media") {
            return AppIcon.Media.waveform
        }
        if normalized.contains("video") || normalized.contains("youtube") {
            return AppIcon.Media.video
        }
        if normalized.contains("web") || normalized.contains("browser") || normalized.contains("internet") {
            return AppIcon.Domain.websites
        }
        if normalized.contains("file") || normalized.contains("document") {
            return AppIcon.Domain.files
        }
        if normalized.contains("task") || normalized.contains("productivity") {
            return AppIcon.Domain.tasks
        }
        if normalized.contains("note") {
            return AppIcon.Content.note
        }
        if normalized.contains("memory") {
            return AppIcon.Skills.memory
        }
        if normalized.contains("setting") || normalized.contains("system") {
            return AppIcon.Settings.appPreferences
        }
        if normalized.contains("developer") || normalized.contains("code") || normalized.contains("tool") {
            return AppIcon.Skills.tools
        }
        return AppIcon.Skills.categoryFallback
    }
}

struct SkillsStoreFilterChip: View {
    let title: String
    let icon: AppIcon
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(appIcon: icon)
                    .appFont(.caption)
                Text(title)
                    .appFont(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : (isHovered ? DesignTokens.Colors.sidebarHoverBackground : DesignTokens.Colors.surface)
                )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .sidebarHover($isHovered)
    }
}

struct SkillsStoreCard: View {
    let skillIconName: String
    let typeTitle: String
    let displayName: String
    let displayDescription: String
    let installError: String?
    let isBusy: Bool
    let isInstalled: Bool
    let onInstall: () -> Void
    let onCardTap: () -> Void
    let onInstalledTap: () -> Void

    private let cardHeight: CGFloat = 96
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onCardTap) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                        SkillAppIcon(systemName: skillIconName)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(typeTitle.uppercased())
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                            Text(displayName)
                                .appFont(.subheading)
                                .lineLimit(1)
                            Text(displayDescription)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let installError, !installError.isEmpty {
                        Text(installError)
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.error)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.trailing, 44 + DesignTokens.Spacing.sm)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityHint("Open skill details")

            installButton
                .padding(.top, 2)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? DesignTokens.Colors.sidebarHoverBackground : DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .accessibilityAddTraits(.isButton)
        .sidebarHover($isHovered)
    }

    private var installButton: some View {
        Group {
            if isInstalled {
                Button(action: onInstalledTap) {
                    SkillsStoreInstallPill(icon: AppIcon.State.successFilled, busy: isBusy)
                }
                .accessibilityLabel("Installed")
            } else {
                Button(action: onInstall) {
                    SkillsStoreInstallPill(icon: AppIcon.Action.addCircleFilled, busy: isBusy)
                }
                .accessibilityLabel("Install")
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

private struct SkillsStoreInstallPill: View {
    let icon: AppIcon
    let busy: Bool

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary)
            } else {
                Image(appIcon: icon)
                    .appFont(.displayMd)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconForeground, Color.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconForeground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}
