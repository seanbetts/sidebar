import SwiftUI
import WidgetKit

struct TaskCountWidget: Widget {
    let kind: String = "TaskCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TaskCountWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task Count")
        .description("Shows today's task count with a tap to open.")
        .supportedFamilies([.systemSmall])
    }
}

struct TaskCountWidgetView: View {
    var entry: TodayTasksEntry

    var body: some View {
        if !entry.isAuthenticated {
            notAuthenticatedView
        } else {
            countView
        }
    }

    private var countView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    .frame(width: 64, height: 64)

                if entry.data.totalCount > 0 {
                    Circle()
                        .trim(from: 0, to: completionProgress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                }

                Text("\(entry.data.totalCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
            }

            Text("Tasks")
                .font(.subheadline)
                .fontWeight(.medium)

            if entry.data.totalCount == 0 {
                Text("All done!")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .widgetAccentable()
            } else {
                Text(entry.data.totalCount == 1 ? "task" : "tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    private var completionProgress: CGFloat {
        // For now, show full circle when there are tasks
        // Could be enhanced to show completed/total ratio
        entry.data.totalCount > 0 ? 1.0 : 0.0
    }

    private var notAuthenticatedView: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Sign in")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Count", as: .systemSmall) {
    TaskCountWidget()
} timeline: {
    TodayTasksEntry.placeholder
}

#Preview("Empty", as: .systemSmall) {
    TaskCountWidget()
} timeline: {
    TodayTasksEntry(date: Date(), data: .empty, isAuthenticated: true)
}
