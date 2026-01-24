import SwiftUI

struct TaskPill: View {
    let text: String
    let iconName: String?

    init(text: String, iconName: String? = nil) {
        self.text = text
        self.iconName = iconName
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(DesignTokens.Colors.muted)
        .clipShape(Capsule())
    }
}

struct TaskRow<MenuContent: View>: View {
    let task: TaskItem
    let subtitle: String
    let dueLabel: String?
    let repeatLabel: String?
    let selection: TaskSelection
    let onComplete: () -> Void
    let onOpenNotes: () -> Void
    let menuContent: () -> MenuContent

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            if task.isPreview {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 20, height: 20)
            } else {
                Button {
                    onComplete()
                } label: {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                    if let notes = task.notes, !notes.isEmpty {
                        Button {
                            onOpenNotes()
                        } label: {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit notes")
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: DesignTokens.Spacing.xs) {
                if showsDuePill, let dueLabel {
                    TaskPill(text: dueLabel)
                }
                if let repeatLabel {
                    TaskPill(text: repeatLabel, iconName: "repeat")
                }
                Menu {
                    menuContent()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(task.isPreview)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var showsDuePill: Bool {
        switch selection {
        case .area, .project, .search:
            return true
        default:
            return false
        }
    }
}
