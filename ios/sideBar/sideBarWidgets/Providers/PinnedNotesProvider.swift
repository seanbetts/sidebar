import WidgetKit
import SwiftUI
import sideBarShared

struct PinnedNotesEntry: TimelineEntry {
    let date: Date
    let data: WidgetNoteData
    let isAuthenticated: Bool
    let selection: NotesWidgetSelection

    static let placeholder = PinnedNotesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true,
        selection: .all
    )

    static let notAuthenticated = PinnedNotesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false,
        selection: .all
    )
}

struct PinnedNotesProvider: AppIntentTimelineProvider {
    typealias Intent = NotesWidgetConfigurationIntent
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
        Self.previewEntry(for: context.family, selection: .all, now: now())
    }

    func snapshot(for configuration: NotesWidgetConfigurationIntent, in context: Context) async -> PinnedNotesEntry {
        if context.isPreview {
            return Self.previewEntry(for: context.family, selection: configuration.selection, now: now())
        }

        let entry = await entry(for: now(), selection: configuration.selection)
        recordProviderDiagnostics(stage: "snapshot", entry: entry)
        return entry
    }

    func timeline(
        for configuration: NotesWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<PinnedNotesEntry> {
        await timeline(for: now(), selection: configuration.selection)
    }

    func timeline(
        for currentDate: Date,
        selection: NotesWidgetSelection = .all
    ) async -> Timeline<PinnedNotesEntry> {
        let entry = await entry(for: currentDate, selection: selection)
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

    func entry(
        for date: Date,
        selection: NotesWidgetSelection = .all
    ) async -> PinnedNotesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .notes)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        let storedData: WidgetNoteData = dataManager.load(for: .notes)
        var data: WidgetNoteData = selection.filter(storedData)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .notes,
            lastUpdated: hasCachedSnapshot ? storedData.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )
        let shouldAttemptScopedEmptyRefresh =
            selection != .all &&
            data.notes.isEmpty

        if decision.shouldAttemptRefresh || shouldAttemptScopedEmptyRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .notes)
                data = selection.filter(refreshed)
            } catch {
                WidgetExtensionDiagnostics.reporter.captureFailure(
                    surface: "widget_provider",
                    stage: "pinned_notes_refresh_failed",
                    message: "Failed to refresh note widget content.",
                    metadata: [
                        "provider": "PinnedNotesProvider",
                        "selection": selection.headerTitle,
                        "scope": selection.scopeDescription,
                        "has_cached_snapshot": hasCachedSnapshot ? "true" : "false",
                        "error": String(describing: error)
                    ]
                )
            }
        }

        return PinnedNotesEntry(
            date: date,
            data: data,
            isAuthenticated: true,
            selection: selection
        )
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

    static func previewEntry(
        for family: WidgetFamily,
        selection: NotesWidgetSelection = .all,
        now: Date = Date()
    ) -> PinnedNotesEntry {
        let previewData = selection.filter(WidgetGalleryPreviewContent.notes(for: family, now: now))
        return PinnedNotesEntry(
            date: now,
            data: previewData,
            isAuthenticated: true,
            selection: selection
        )
    }
}

private extension NotesWidgetSelection {
    var scopeDescription: String {
        switch self {
        case .all:
            return "all"
        case .folder(let path, _):
            return path
        }
    }
}
