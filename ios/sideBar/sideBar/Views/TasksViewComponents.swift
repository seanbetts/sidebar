import SwiftUI

struct TaskPill: View {
    let text: String
    let iconName: String?
    @Environment(\.colorScheme) private var colorScheme

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
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(pillBackground)
        .overlay(
            Capsule()
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var pillBackground: Color {
        colorScheme == .dark ? .black : .white
    }
}

struct TaskRow<MenuContent: View>: View {
    let task: TaskItem
    let dueLabel: String?
    let repeatLabel: String?
    let selection: TaskSelection
    let onComplete: () -> Void
    let onOpenNotes: () -> Void
    let onSelect: () -> Void
    let menuContent: () -> MenuContent
    @State private var showRepeatInfo = false
    @State private var isCompleting = false

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            if task.isPreview {
                Button {
                    if repeatLabel != nil {
                        showRepeatInfo = true
                    }
                } label: {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Repeat details")
                .alert("Repeats", isPresented: $showRepeatInfo) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(repeatLabel ?? "")
                }
            } else {
                Button {
                    guard !isCompleting else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCompleting = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                } label: {
                    Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(isCompleting ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(isCompleting)
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
                            Image(systemName: "text.document")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit notes")
                    }
                }
            }
            Spacer()
            HStack(spacing: DesignTokens.Spacing.xs) {
                if showsDuePill, let dueLabel {
                    TaskPill(text: dueLabel)
                }
                if TasksUtils.isOverdue(task) {
                    TaskPill(text: "Overdue", iconName: "exclamationmark.circle")
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
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var showsDuePill: Bool {
        switch selection {
        case .group, .project, .search:
            return true
        default:
            return false
        }
    }
}
