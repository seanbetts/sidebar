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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    .frame(width: 64, height: 64)

                if entry.data.totalCount > 0 {
                    Circle()
                        .trim(from: 0, to: completionProgress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "sidebar://tasks/today"))
    }

    private var completionProgress: CGFloat {
        let total = max(entry.data.progressTotalCount, 0)
        guard total > 0 else { return 0.0 }
        let completed = min(max(entry.data.progressCompletedCount, 0), total)
        return CGFloat(completed) / CGFloat(total)
    }

    private var notAuthenticatedView: some View {
        HomeWidgetSignedOutView(content: .tasks)
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
