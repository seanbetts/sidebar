import SwiftUI

enum SkillsStoreCategoryIcon {
    static func iconName(for raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized == "all" { return "square.grid.2x2" }
        if normalized.contains("audio") || normalized.contains("media") {
            return "waveform"
        }
        if normalized.contains("video") || normalized.contains("youtube") {
            return "play.rectangle"
        }
        if normalized.contains("web") || normalized.contains("browser") || normalized.contains("internet") {
            return "globe"
        }
        if normalized.contains("file") || normalized.contains("document") {
            return "folder"
        }
        if normalized.contains("task") || normalized.contains("productivity") {
            return "checkmark.square"
        }
        if normalized.contains("note") {
            return "note.text"
        }
        if normalized.contains("memory") {
            return "brain"
        }
        if normalized.contains("setting") || normalized.contains("system") {
            return "gearshape"
        }
        if normalized.contains("developer") || normalized.contains("code") || normalized.contains("tool") {
            return "hammer"
        }
        return "tag.fill"
    }
}

struct SkillsStoreFilterChip: View {
    let title: String
    let iconName: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : DesignTokens.Colors.surface
                )
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                Button(action: onCardTap) {
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                        SkillsStoreAppIcon(iconName: skillIconName)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(typeTitle.uppercased())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(displayName)
                                .font(DesignTokens.Typography.subheadlineSemibold)
                                .lineLimit(1)
                            Text(displayDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityHint("Open skill details")

                installButton
                    .padding(.top, 2)
            }

            if let installError, !installError.isEmpty {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .lineLimit(1)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var installButton: some View {
        Group {
            if isInstalled {
                Button(action: onInstalledTap) {
                    SkillsStoreInstallPill(systemName: "checkmark.circle.fill", busy: isBusy)
                }
                .accessibilityLabel("Installed")
            } else {
                Button(action: onInstall) {
                    SkillsStoreInstallPill(systemName: "plus.circle.fill", busy: isBusy)
                }
                .accessibilityLabel("Install")
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }
}

private struct SkillsStoreAppIcon: View {
    let iconName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
            Image(systemName: iconName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.75))
        }
        .frame(width: 62, height: 62)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }
}

private struct SkillsStoreInstallPill: View {
    let systemName: String
    let busy: Bool

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .semibold))
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
