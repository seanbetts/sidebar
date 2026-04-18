import AppIntents
import SwiftUI
import WidgetKit
import sideBarShared

#if os(iOS)
// MARK: - Lock Screen Task Count (Circular)

struct LockScreenTaskCountWidget: Widget {
    let kind: String = "LockScreenTaskCount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TaskWidgetConfigurationIntent.self, provider: TodayTasksProvider()) { entry in
            LockScreenTaskCountView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task Count")
        .description("Shows today's task count.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockScreenTaskCountView: View {
    var entry: TodayTasksEntry

    var body: some View {
        if entry.isAuthenticated {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.data.totalCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .widgetAccentable()
                    Text("tasks")
                        .font(.system(size: 8))
                        .textCase(.uppercase)
                }
            }
            .widgetURL(entry.selection.deepLinkURL)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checklist")
            }
        }
    }
}

// MARK: - Lock Screen Task Preview (Rectangular)

struct LockScreenTaskPreviewWidget: Widget {
    let kind: String = "LockScreenTaskPreview"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TaskWidgetConfigurationIntent.self, provider: TodayTasksProvider()) { entry in
            LockScreenTaskPreviewView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Tasks")
        .description("Shows your next tasks for today.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockScreenTaskPreviewView: View {
    var entry: TodayTasksEntry

    var body: some View {
        if !entry.isAuthenticated {
            LockScreenSignedOutRow(iconSystemName: "checklist")
        } else if visibleTasks.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("All done for today!")
                    .font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visibleTasks.prefix(2)) { task in
                    Button(intent: CompleteTaskIntent(taskId: task.id, selectionKey: entry.selection.cacheKey)) {
                        HStack(spacing: 4) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8))
                            Text(task.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if visibleTasks.count > 2 {
                    Text("+\(visibleTasks.count - 2) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entry.selection.deepLinkURL)
        }
    }

    private var visibleTasks: [WidgetTask] {
        WidgetTasksUtils.sortByDueDate(
            WidgetTasksUtils.visibleTasks(entry.data.tasks, now: entry.date)
        )
    }
}

// MARK: - Lock Screen Inline

struct LockScreenInlineWidget: Widget {
    let kind: String = "LockScreenInline"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TaskWidgetConfigurationIntent.self, provider: TodayTasksProvider()) { entry in
            LockScreenInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks Inline")
        .description("Shows task count inline on lock screen.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockScreenInlineView: View {
    var entry: TodayTasksEntry

    var body: some View {
        if entry.isAuthenticated {
            if entry.data.totalCount == 0 {
                Label("All done!", systemImage: "checkmark.circle")
            } else {
                Label(
                    "\(entry.data.totalCount) task\(entry.data.totalCount == 1 ? "" : "s") today",
                    systemImage: "checklist"
                )
            }
        } else {
            Label("sideBar", systemImage: "checklist")
        }
    }
}

// MARK: - Previews

#Preview("Circular", as: .accessoryCircular) {
    LockScreenTaskCountWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LockScreenTaskPreviewWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Inline", as: .accessoryInline) {
    LockScreenInlineWidget()
} timeline: {
    TodayTasksEntry.placeholder
}
#endif
