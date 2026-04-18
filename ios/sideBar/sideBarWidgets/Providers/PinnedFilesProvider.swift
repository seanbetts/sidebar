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

    private let dataManager: WidgetDataManager
    private let now: () -> Date
    private let refreshData: @Sendable (Date) async throws -> WidgetFileData

    init(
        dataManager: WidgetDataManager = .shared,
        now: @escaping () -> Date = Date.init,
        refreshData: @escaping @Sendable (Date) async throws -> WidgetFileData = { currentDate in
            let environment = try WidgetAPIEnvironment()
            return try await FilesWidgetRefreshClient(environment: environment)
                .refreshPinnedFiles(now: currentDate)
        }
    ) {
        self.dataManager = dataManager
        self.now = now
        self.refreshData = refreshData
    }

    func placeholder(in context: Context) -> PinnedFilesEntry {
        Self.previewEntry(for: context.family, now: now())
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedFilesEntry) -> Void) {
        if context.isPreview {
            completion(Self.previewEntry(for: context.family, now: now()))
            return
        }

        Task {
            let entry = await entry(for: now())
            recordProviderDiagnostics(stage: "snapshot", entry: entry)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedFilesEntry>) -> Void) {
        Task {
            completion(await timeline(for: now()))
        }
    }

    func timeline(for currentDate: Date) async -> Timeline<PinnedFilesEntry> {
        let entry = await entry(for: currentDate)
        recordProviderDiagnostics(stage: "timeline", entry: entry)
        guard entry.isAuthenticated else {
            return Timeline(entries: [entry], policy: .after(nextMidnight(from: currentDate)))
        }
        let nextUpdate = WidgetRefreshPolicy.nextRefreshDate(
            lastUpdated: entry.data.lastUpdated,
            contentType: .files,
            now: currentDate
        )
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    func entry(for date: Date) async -> PinnedFilesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .files)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        var data: WidgetFileData = dataManager.load(for: .files)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .files,
            lastUpdated: hasCachedSnapshot ? data.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .files)
                data = refreshed
            } catch {}
        }

        return PinnedFilesEntry(date: date, data: data, isAuthenticated: true)
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

    private func nextMidnight(from date: Date) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: tomorrow)
    }

    static func previewEntry(for family: WidgetFamily, now: Date = Date()) -> PinnedFilesEntry {
        PinnedFilesEntry(
            date: now,
            data: WidgetGalleryPreviewContent.files(for: family, now: now),
            isAuthenticated: true
        )
    }
}
