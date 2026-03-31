import WidgetKit
import SwiftUI
import sideBarShared

struct PinnedFilesEntry: TimelineEntry {
    let date: Date
    let data: WidgetFileData
    let isAuthenticated: Bool

    static let placeholder = PinnedFilesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = PinnedFilesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct PinnedFilesProvider: TimelineProvider {
    typealias Entry = PinnedFilesEntry

    func placeholder(in context: Context) -> PinnedFilesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedFilesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        let entry = createEntry()
        recordProviderDiagnostics(stage: "snapshot", entry: entry)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedFilesEntry>) -> Void) {
        let entry = createEntry()
        recordProviderDiagnostics(stage: "timeline", entry: entry)

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> PinnedFilesEntry {
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: WidgetDataManager.shared.isAuthenticated(),
            hasCachedSnapshot: WidgetDataManager.shared.hasStoredSnapshot(for: .files)
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        let data: WidgetFileData = WidgetDataManager.shared.load(for: .files)
        return PinnedFilesEntry(date: Date(), data: data, isAuthenticated: true)
    }

    private func recordProviderDiagnostics(stage: String, entry: PinnedFilesEntry) {
        WidgetExtensionDiagnostics.reporter.recordBreadcrumb(
            surface: "widget_provider",
            stage: stage,
            message: "Built files widget entry.",
            metadata: [
                "provider": "PinnedFilesProvider",
                "is_authenticated": entry.isAuthenticated ? "true" : "false",
                "item_count": "\(entry.data.files.count)",
                "total_count": "\(entry.data.totalCount)"
            ]
        )
    }
}
