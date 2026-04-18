import WidgetKit
import SwiftUI
import sideBarShared

struct PinnedNotesEntry: TimelineEntry {
    let date: Date
    let data: WidgetNoteData
    let isAuthenticated: Bool

    static let placeholder = PinnedNotesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true
    )

    static let notAuthenticated = PinnedNotesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false
    )
}

struct PinnedNotesProvider: TimelineProvider {
    typealias Entry = PinnedNotesEntry

    private let dataManager: WidgetDataManager
    private let now: () -> Date
    private let refreshData: @Sendable (Date) async throws -> WidgetNoteData

    init(
        dataManager: WidgetDataManager = .shared,
        now: @escaping () -> Date = Date.init,
        refreshData: @escaping @Sendable (Date) async throws -> WidgetNoteData = { currentDate in
            let environment = try WidgetAPIEnvironment()
            return try await NotesWidgetRefreshClient(environment: environment)
                .refreshPinnedNotes(now: currentDate)
        }
    ) {
        self.dataManager = dataManager
        self.now = now
        self.refreshData = refreshData
    }

    func placeholder(in context: Context) -> PinnedNotesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedNotesEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }

        Task {
            let entry = await entry(for: now())
            recordProviderDiagnostics(stage: "snapshot", entry: entry)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedNotesEntry>) -> Void) {
        Task {
            completion(await timeline(for: now()))
        }
    }

    func timeline(for currentDate: Date) async -> Timeline<PinnedNotesEntry> {
        let entry = await entry(for: currentDate)
        recordProviderDiagnostics(stage: "timeline", entry: entry)
        guard entry.isAuthenticated else {
            return Timeline(entries: [entry], policy: .after(nextMidnight(from: currentDate)))
        }
        let nextUpdate = WidgetRefreshPolicy.nextRefreshDate(
            lastUpdated: entry.data.lastUpdated,
            contentType: .notes,
            now: currentDate
        )
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func entry(for date: Date) async -> PinnedNotesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .notes)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        var data: WidgetNoteData = dataManager.load(for: .notes)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .notes,
            lastUpdated: hasCachedSnapshot ? data.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .notes)
                data = refreshed
            } catch {}
        }

        return PinnedNotesEntry(date: date, data: data, isAuthenticated: true)
    }

    private func recordProviderDiagnostics(stage: String, entry: PinnedNotesEntry) {
        WidgetExtensionDiagnostics.reporter.recordBreadcrumb(
            surface: "widget_provider",
            stage: stage,
            message: "Built note widget entry.",
            metadata: [
                "provider": "PinnedNotesProvider",
                "is_authenticated": entry.isAuthenticated ? "true" : "false",
                "item_count": "\(entry.data.notes.count)",
                "total_count": "\(entry.data.totalCount)"
            ]
        )
    }

    private func nextMidnight(from date: Date) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: tomorrow)
    }
}
