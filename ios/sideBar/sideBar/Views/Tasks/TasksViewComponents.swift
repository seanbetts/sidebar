import SwiftUI

func taskRowTapGestureMask() -> GestureMask {
    .gesture
}

enum TaskRowCompletionAction: Equatable {
    case complete
    case reopen
}

func taskRowCompletionAction(
    selection: TaskSelection,
    taskStatus: String
) -> TaskRowCompletionAction {
    if selection == .completed || taskStatus == "completed" {
        return .reopen
    }
    return .complete
}

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
                    .appFont(.caption2)
            }
            Text(text)
                .appFont(.caption2)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
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
    let isExpanded: Bool
    let onComplete: () -> Void
    let onOpenNotes: () -> Void
    let onOpenDue: () -> Void
    let onSelect: () -> Void
    let onToggleExpanded: () -> Void
    let onMove: () -> Void
    let onRepeat: () -> Void
    let onDelete: () -> Void
    let menuContent: () -> MenuContent
    @State private var showRepeatInfo = false
    @State private var isCompleting = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                if task.isPreview {
                    Button {
                        if repeatLabel != nil {
                            showRepeatInfo = true
                        }
                    } label: {
                        Image(systemName: "repeat")
                            .appFont(.caption)
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
                    let completionAction = taskRowCompletionAction(
                        selection: selection,
                        taskStatus: task.status
                    )
                    let isCompleted = completionAction == .reopen
                    Button {
                        guard !isCompleting else { return }
                        switch completionAction {
                        case .complete:
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isCompleting = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                Haptics.notification(.success)
                                onComplete()
                            }
                        case .reopen:
                            onComplete()
                        }
                    } label: {
                        if isCompleted {
                            ZStack {
                                Circle()
                                    .fill(checkboxFillColor)
                                    .opacity(1)
                                    .frame(width: 20, height: 20)
                                Image(systemName: "checkmark")
                                    .appFont(.captionSemibold)
                                    .foregroundStyle(checkboxMarkColor)
                                    .opacity(1)
                            }
                        } else {
                            Group {
                                if isCompleting {
                                    SuccessCheckBadge(size: 20, symbolSize: 11)
                                } else {
                                    Image(systemName: "circle")
                                        .appFont(.body)
                                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                                }
                            }
                            .frame(width: 20, height: 20)
                            .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isCompleting)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .appFont(.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 1)
                            .fixedSize(horizontal: false, vertical: isExpanded)
                        if let notes = task.notes, !notes.isEmpty {
                            Button {
                                onOpenNotes()
                            } label: {
                                Image(systemName: "text.document")
                                    .appFont(.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit notes")
                        }
                    }
                }
                Spacer()
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if selection != .completed && TasksUtils.isOverdue(task) {
                        if isCompact {
                            Image(systemName: "exclamationmark.circle")
                                .appFont(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        } else {
                            TaskPill(text: "Overdue", iconName: "exclamationmark.circle")
                                .overlay(isExpanded ? pillBorder : nil)
                        }
                    }
                    if showsDuePill, let dueLabel {
                        Button {
                            onOpenDue()
                        } label: {
                            TaskPill(text: dueLabel)
                                .overlay(isExpanded ? pillBorder : nil)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set due date")
                    }
                    if selection == .completed {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .appFont(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Menu {
                            menuContent()
                        } label: {
                            Image(systemName: "ellipsis")
                                .appFont(.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isPreview)
                    }
                }
            }
            .padding(.top, DesignTokens.Spacing.xxs)
            .padding(.bottom, DesignTokens.Spacing.xxxs)
            .padding(.horizontal, DesignTokens.Spacing.sm)

            if isExpanded {
                expandedContent
                    .transition(detailTransition)
            }
        }
        .background(isExpanded ? DesignTokens.Colors.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded {
                onSelect()
                withAnimation(expandAnimation) {
                    onToggleExpanded()
                }
            },
            including: taskRowTapGestureMask()
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
            Text(task.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? task.notes ?? ""
                : "No notes")
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignTokens.Spacing.sm)
            HStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    onOpenDue()
                } label: {
                    if let dueLabel {
                        TaskPill(text: dueLabel)
                            .overlay(pillBorder)
                    } else {
                        TaskPill(text: "No due date")
                            .overlay(pillBorder)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set due date")
                Spacer()
                if selection != .completed {
                    Button {
                        onMove()
                    } label: {
                        Image(systemName: "folder")
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding(DesignTokens.Spacing.xxxs)
                    }
                    .buttonStyle(.plain)
                    Button {
                        onRepeat()
                    } label: {
                        Image(systemName: "repeat")
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .padding(DesignTokens.Spacing.xxxs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.leading, DesignTokens.Spacing.sm + 22 + DesignTokens.Spacing.sm)
        .padding(.trailing, DesignTokens.Spacing.sm)
        .padding(.top, 0)
        .padding(.bottom, DesignTokens.Spacing.md)
        .clipped()
    }

    private var pillBorder: some View {
        RoundedRectangle(cornerRadius: 999)
            .stroke(pillBorderColor, lineWidth: 1)
    }

    private var pillBorderColor: Color {
        colorScheme == .dark
            ? DesignTokens.Colors.textSecondary.opacity(0.45)
            : DesignTokens.Colors.textSecondary.opacity(0.3)
    }

    private var checkboxFillColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var checkboxMarkColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var expandAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.15)
        }
        if #available(iOS 17.0, macOS 14.0, *) {
            return .snappy(duration: 0.22, extraBounce: 0.0)
        }
        return .spring(response: 0.28, dampingFraction: 0.9, blendDuration: 0.1)
    }

    private var showsDuePill: Bool {
        switch selection {
        case .group, .project, .search:
            return true
        default:
            return false
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}
