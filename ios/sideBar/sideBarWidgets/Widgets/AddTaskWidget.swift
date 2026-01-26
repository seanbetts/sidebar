import SwiftUI
import WidgetKit

struct AddTaskWidget: Widget {
    let kind: String = "AddTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AddTaskProvider()) { entry in
            AddTaskWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Add Task")
        .description("Quickly add a new task to sideBar.")
        .supportedFamilies([.systemSmall])
    }
}

struct AddTaskEntry: TimelineEntry {
    let date: Date
    let isAuthenticated: Bool

    static let authenticated = AddTaskEntry(date: Date(), isAuthenticated: true)
    static let notAuthenticated = AddTaskEntry(date: Date(), isAuthenticated: false)
}

struct AddTaskProvider: TimelineProvider {
    typealias Entry = AddTaskEntry

    func placeholder(in context: Context) -> AddTaskEntry {
        .authenticated
    }

    func getSnapshot(in context: Context, completion: @escaping (AddTaskEntry) -> Void) {
        let isAuth = WidgetDataManager.shared.isAuthenticated()
        completion(AddTaskEntry(date: Date(), isAuthenticated: isAuth))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AddTaskEntry>) -> Void) {
        let isAuth = WidgetDataManager.shared.isAuthenticated()
        let entry = AddTaskEntry(date: Date(), isAuthenticated: isAuth)
        // Refresh every hour (auth state doesn't change often)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AddTaskWidgetView: View {
    var entry: AddTaskEntry

    var body: some View {
        if entry.isAuthenticated {
            Button(intent: AddTaskIntent()) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("Add Task")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        } else {
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
}

#Preview("Add Task", as: .systemSmall) {
    AddTaskWidget()
} timeline: {
    AddTaskEntry.authenticated
}

#Preview("Not Auth", as: .systemSmall) {
    AddTaskWidget()
} timeline: {
    AddTaskEntry.notAuthenticated
}
