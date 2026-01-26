import AppIntents
import SwiftUI
import WidgetKit

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

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else if entry.data.tasks.isEmpty {
            emptyStateView
        } else {
            taskListView
        }
    }

    // MARK: - Task List View

    private var taskListView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                headerView
                Spacer(minLength: 4)
                tasksList
                if showMoreIndicator {
                    moreTasksIndicator
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Add task button
            addTaskButton
        }
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    private var headerView: some View {
        HStack {
            Text("Today")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            if entry.data.totalCount > 0 {
                Text("\(entry.data.totalCount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tasksList: some View {
        VStack(alignment: .leading, spacing: taskSpacing) {
            ForEach(displayedTasks) { task in
                TaskRowView(task: task, compact: family == .systemSmall)
            }
        }
    }

    private var displayedTasks: [WidgetTask] {
        Array(entry.data.tasks.prefix(maxTasks))
    }

    private var maxTasks: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }

    private var taskSpacing: CGFloat {
        switch family {
        case .systemSmall: return 6
        case .systemMedium: return 8
        case .systemLarge: return 10
        default: return 8
        }
    }

    private var showMoreIndicator: Bool {
        entry.data.totalCount > displayedTasks.count
    }

    private var moreTasksIndicator: some View {
        Text("+\(entry.data.totalCount - displayedTasks.count) more")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
    }

    private var addTaskButton: some View {
        Button(intent: AddTaskIntent()) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: family == .systemSmall ? 20 : 24))
                .foregroundStyle(.white, Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("All done!")
                    .font(.headline)
                Text("No tasks for today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            addTaskButton
        }
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    // MARK: - Not Authenticated

    private var notAuthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Sign in to sideBar")
                .font(.headline)
            Text("to see your tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: WidgetTask
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Interactive checkbox button
            Button(intent: CompleteTaskIntent(taskId: task.id)) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 16 : 18))
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(compact ? .caption : .subheadline)
                    .lineLimit(1)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                if !compact, let projectName = task.projectName {
                    Text(projectName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
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
