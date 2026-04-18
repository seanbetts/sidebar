import WidgetKit
import SwiftUI
import sideBarShared

struct PinnedFilesEntry: TimelineEntry {
    let date: Date
    let data: WidgetFileData
    let isAuthenticated: Bool
    let selection: FileWidgetSelection

    static let placeholder = PinnedFilesEntry(
        date: Date(),
        data: .placeholder,
        isAuthenticated: true,
        selection: .all
    )

    static let notAuthenticated = PinnedFilesEntry(
        date: Date(),
        data: .empty,
        isAuthenticated: false,
        selection: .all
    )
}

struct PinnedFilesProvider: AppIntentTimelineProvider {
    typealias Intent = FilesWidgetConfigurationIntent
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
        Self.previewEntry(for: context.family, selection: .all, now: now())
    }

    func snapshot(for configuration: FilesWidgetConfigurationIntent, in context: Context) async -> PinnedFilesEntry {
        if context.isPreview {
            return Self.previewEntry(for: context.family, selection: configuration.selection, now: now())
        }

        let entry = await entry(for: now(), selection: configuration.selection)
        recordProviderDiagnostics(stage: "snapshot", entry: entry)
        return entry
    }

    func timeline(
        for configuration: FilesWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<PinnedFilesEntry> {
        await timeline(for: now(), selection: configuration.selection)
    }

    func timeline(
        for currentDate: Date,
        selection: FileWidgetSelection = .all
    ) async -> Timeline<PinnedFilesEntry> {
        let entry = await entry(for: currentDate, selection: selection)
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

    func entry(
        for date: Date,
        selection: FileWidgetSelection = .all
    ) async -> PinnedFilesEntry {
        let hasCachedSnapshot = dataManager.hasStoredSnapshot(for: .files)
        let isAuthenticated = dataManager.isAuthenticated()
        let canDisplayContent = WidgetDisplayAuthorization.canDisplayContent(
            isAuthenticated: isAuthenticated,
            hasCachedSnapshot: hasCachedSnapshot
        )
        guard canDisplayContent else {
            return .notAuthenticated
        }

        let storedData: WidgetFileData = dataManager.load(for: .files)
        var data: WidgetFileData = selection.filter(storedData)
        let decision = WidgetRefreshCoordinator.decision(
            contentType: .files,
            lastUpdated: hasCachedSnapshot ? storedData.lastUpdated : nil,
            hasCachedSnapshot: hasCachedSnapshot,
            isAuthenticated: isAuthenticated,
            now: date
        )

        if decision.shouldAttemptRefresh {
            do {
                let refreshed = try await refreshData(date)
                dataManager.store(refreshed, for: .files)
                data = selection.filter(refreshed)
            } catch {
                let appError = AppError.classify(
                    error: error,
                    operation: "widget.files.refresh",
                    requestKind: .foregroundRead
                )
                var metadata = appError.diagnostics
                metadata["provider"] = "PinnedFilesProvider"
                metadata["selection"] = selection.headerTitle
                metadata["has_cached_snapshot"] = hasCachedSnapshot ? "true" : "false"
                WidgetExtensionDiagnostics.reporter.captureFailure(
                    surface: "widget_provider",
                    stage: "pinned_files_refresh_failed",
                    message: "Failed to refresh files widget content.",
                    metadata: metadata
                )
            }
        }

        return PinnedFilesEntry(
            date: date,
            data: data,
            isAuthenticated: true,
            selection: selection
        )
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

    static func previewEntry(
        for family: WidgetFamily,
        selection: FileWidgetSelection = .all,
        now: Date = Date()
    ) -> PinnedFilesEntry {
        let previewData = selection.filter(WidgetGalleryPreviewContent.files(for: family, now: now))
        return PinnedFilesEntry(
            date: now,
            data: previewData,
            isAuthenticated: true,
            selection: selection
        )
    }
}
