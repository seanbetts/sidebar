import AppIntents
import SwiftUI
import WidgetKit
import sideBarShared

struct TodayTasksWidget: Widget {
    let kind: String = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Tasks")
        .description("View and complete today's tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget View

struct TodayTasksWidgetView: View {
    var entry: TodayTasksEntry

    @Environment(\.widgetFamily) var family
    @Environment(\.widgetRenderingMode) var renderingMode
    @Environment(\.showsWidgetContainerBackground) var showsWidgetContainerBackground
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else if visibleTasks.isEmpty {
            emptyStateView
        } else {
            taskListView
        }
    }

    // MARK: - Task List View

    private var taskListView: some View {
        Group {
            if usesStandByLayout {
                standByTaskListView
            } else {
                standardTaskListView
            }
        }
    }

    private var tasksList: some View {
        VStack(alignment: .leading, spacing: taskSpacing) {
            ForEach(displayedTasks) { task in
                TaskRowView(
                    task: task,
                    compact: isCompact,
                    standBy: usesStandByLayout,
                    showSubtitle: showSubtitle
                )
            }
        }
    }

    private var standardTaskListView: some View {
        WidgetListLayout(family: family) {
            WidgetHeaderView(
                title: "Tasks",
                totalCount: entry.data.totalCount,
                destination: URL(string: "sidebar://tasks/today")!,
                reduceTitleForSmall: false,
                family: family
            )
        } list: {
            tasksList
        } footer: {
            HStack {
                if showMoreIndicator {
                    moreTasksIndicator
                }
                Spacer()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            addTaskButton
        }
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    private var standByTaskListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                if entry.data.totalCount > 0 {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                addTaskButton
            }

            tasksList

            if showMoreIndicator {
                moreTasksIndicator
                    .font(.footnote.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    private var visibleTasks: [WidgetTask] {
        WidgetTasksUtils.sortByDueDate(
            WidgetTasksUtils.visibleTasks(entry.data.tasks, now: entry.date)
        )
    }

    private var displayedTasks: [WidgetTask] {
        Array(visibleTasks.prefix(maxTasks))
    }

    private var maxTasks: Int {
        switch family {
        case .systemSmall: return usesStandByLayout ? 2 : 3
        case .systemMedium: return 3  // Same height as small
        case .systemLarge: return 8
        default: return 3
        }
    }

    private var taskSpacing: CGFloat {
        switch family {
        case .systemSmall: return usesStandByLayout ? 10 : 6
        case .systemMedium: return 6  // Same height as small
        case .systemLarge: return 10
        default: return 6
        }
    }

    private var isCompact: Bool {
        family == .systemSmall && !usesStandByLayout
    }

    private var showSubtitle: Bool {
        family == .systemLarge
    }

    private var usesStandByLayout: Bool {
        family == .systemSmall && !showsWidgetContainerBackground
    }

    private var showMoreIndicator: Bool {
        entry.data.totalCount > displayedTasks.count
    }

    private var moreTasksIndicator: some View {
        Text("+\(entry.data.totalCount - displayedTasks.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var addTaskButton: some View {
        Group {
            if #available(iOS 17.0, *) {
                Button(intent: AddTaskIntent()) {
                    addTaskButtonContent
                }
            } else {
                Link(destination: URL(string: "sidebar://tasks/new")!) {
                    addTaskButtonContent
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var buttonSize: CGFloat {
        family == .systemSmall ? 20 : 24
    }

    @ViewBuilder
    private var addTaskButtonContent: some View {
        switch renderingMode {
        case .fullColor:
            // Default/Dark mode: contrasting colors
            if colorScheme == .dark {
                // Dark mode: black + on white background
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(.white))
            } else {
                // Light mode: white + on black background
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Circle().fill(.black))
            }
        case .accented:
            // Clear/Tinted mode: + gets accent color (tint), background is tertiary fill
            ZStack {
                Circle()
                    .fill(.fill.tertiary)
                    .frame(width: buttonSize, height: buttonSize)
                Image(systemName: "plus")
                    .font(.system(size: buttonSize * 0.5, weight: .bold))
                    .widgetAccentable()
            }
        default:
            // Fallback (vibrant mode, etc.)
            Image(systemName: "plus")
                .font(.system(size: buttonSize * 0.5, weight: .bold))
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(.fill.tertiary))
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        Group {
            if usesStandByLayout {
                standByEmptyStateView
            } else {
                HomeWidgetEmptyStateView(
                    title: "All done!",
                    subtitle: "No tasks for today",
                    iconSystemName: "checkmark.circle",
                    destination: URL(string: "sidebar://tasks/today")!,
                    accentIcon: false
                ) {
                    addTaskButton
                }
            }
        }
    }

    private var standByEmptyStateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("All done!")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                addTaskButton
            }

            Text("No tasks for today")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        HomeWidgetSignedOutView(content: .tasks)
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: WidgetTask
    let compact: Bool
    let standBy: Bool
    let showSubtitle: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            // Interactive checkbox button
            Button(intent: CompleteTaskIntent(taskId: task.id)) {
                checkboxIcon
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(titleFont)
                    .lineLimit(standBy ? 2 : 1)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if showSubtitle, let subtitle = task.projectName ?? task.groupName {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            if WidgetTasksUtils.isOverdue(task) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .widgetAccentable(false)
            }
        }
    }

    @ViewBuilder
    private var checkboxIcon: some View {
        let iconSize: CGFloat = standBy ? 20 : (compact ? 16 : 18)
        if task.isCompleted {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                Image(systemName: "checkmark")
                    .font(.system(size: iconSize * 0.55, weight: .bold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }
            .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: "circle")
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
        }
    }

    private var titleFont: Font {
        if standBy {
            return .system(size: 15, weight: .semibold, design: .rounded)
        }
        return compact ? .caption : .subheadline
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry(date: Date(), data: .empty, isAuthenticated: true)
}

#Preview("Not Authenticated", as: .systemMedium) {
    TodayTasksWidget()
} timeline: {
    TodayTasksEntry.notAuthenticated
}
