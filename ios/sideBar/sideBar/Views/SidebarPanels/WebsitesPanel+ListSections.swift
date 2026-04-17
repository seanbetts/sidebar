import Foundation
import sideBarShared
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension WebsitesPanelView {
    enum PanelState: Equatable {
        case loading
        case error
        case search
        case empty
        case content
        case sparse
    }

    enum ListSectionLayout: Equatable {
        case sparseState
        case primaryContent
        case archive
    }

    static func resolvedSelectionID(
        transientSelection: String?,
        selectedWebsiteId: String?,
        activeWebsiteId: String?
    ) -> String? {
        transientSelection ?? selectedWebsiteId ?? activeWebsiteId
    }

    var currentSelectionID: String? {
        Self.resolvedSelectionID(
            transientSelection: selection,
            selectedWebsiteId: viewModel.selectedWebsiteId,
            activeWebsiteId: viewModel.active?.id
        )
    }

    static let sparseStateTitle = "No websites yet"
    static let sparseStateSubtitle: String? = nil

    static func resolvePanelState(
        isLoading: Bool,
        hasError: Bool,
        hasLoadedContent: Bool,
        panelSearchQuery: String,
        pinnedCount: Int,
        mainCount: Int,
        pendingCount: Int
    ) -> PanelState {
        if isLoading && !hasLoadedContent {
            return .loading
        }
        if hasError && !hasLoadedContent {
            return .error
        }
        if !panelSearchQuery.trimmed.isEmpty {
            return .search
        }
        return (pinnedCount == 0 && mainCount == 0 && pendingCount == 0) ? .sparse : .content
    }

    static func listSectionLayout(
        panelState: PanelState,
        hasPinnedItems: Bool,
        hasMainItems: Bool,
        hasPendingItems: Bool
    ) -> [ListSectionLayout] {
        switch panelState {
        case .sparse:
            return [.sparseState, .archive]
        case .content:
            let hasPrimaryContent = hasPinnedItems || hasMainItems || hasPendingItems
            return hasPrimaryContent ? [.primaryContent] : []
        case .loading, .error, .search, .empty:
            return []
        }
    }

    var panelState: PanelState {
        let visiblePendingCount = viewModel.visiblePendingWebsites.count
        let resolvedState = Self.resolvePanelState(
            isLoading: viewModel.isLoading,
            hasError: viewModel.errorMessage != nil,
            hasLoadedContent: !viewModel.items.isEmpty || visiblePendingCount > 0,
            panelSearchQuery: viewModel.panelSearchQuery,
            pinnedCount: pinnedItemsSorted.count,
            mainCount: mainItems.count,
            pendingCount: visiblePendingCount
        )
        if resolvedState == .sparse && !hasArchivedContent {
            return .empty
        }
        return resolvedState
    }

    var listSectionLayout: [ListSectionLayout] {
        var sections = Self.listSectionLayout(
            panelState: panelState,
            hasPinnedItems: !pinnedItemsSorted.isEmpty,
            hasMainItems: !mainItems.isEmpty,
            hasPendingItems: !viewModel.visiblePendingWebsites.isEmpty
        )
        if hasArchivedContent &&
            !sections.contains(.archive) &&
            (panelState == .content || panelState == .sparse) {
            sections.append(.archive)
        }
        return sections
    }

    func open(item: WebsiteItem) {
        selection = item.id
        Task { await viewModel.selectWebsite(id: item.id) }
    }

    @ViewBuilder
    func websitesPanelList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        sidebarPanelList {
            content()
        }
    }

    func navigateWebsitesList(direction: ShortcutListDirection) {
        let ids = websitesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = currentSelectionID
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        let nextId = ids[nextIndex]
        if let item = viewModel.items.first(where: { $0.id == nextId }) {
            open(item: item)
        }
    }

    func websitesNavigationItems() -> [String] {
        viewModel.panelNavigationWebsiteIds
    }

    @ViewBuilder
    func websiteListRow(
        item: WebsiteItem,
        index: Int,
        useListStyling: Bool = true,
        allowArchive: Bool
    ) -> some View {
        let isSelected = currentSelectionID == item.id
        let row = WebsiteRow(
            item: item,
            isSelected: isSelected,
            useListStyling: useListStyling,
            faviconBaseUrl: appEnvironment.container.config.r2Endpoint,
            r2FaviconBucket: appEnvironment.container.config.r2FaviconBucket,
            r2FaviconPublicBaseUrl: appEnvironment.container.config.r2FaviconPublicBaseUrl,
            onSelect: websiteRowPrimaryAction(for: item)
        )
        .staggeredAppear(index: index, isActive: listAppeared)
        .platformContextMenu(items: websiteContextMenuItemsList(for: item))
        row
    }

    @ViewBuilder
    func pendingWebsiteListRow(
        pending: WebsitesViewModel.PendingWebsiteItem,
        useListStyling: Bool = true
    ) -> some View {
        PendingWebsiteRow(
            pending: pending,
            useListStyling: useListStyling,
            onRetry: {
                if let queueItemId = pending.queueItemId {
                    Task {
                        await appEnvironment.retryPendingQueuedWebsite(queueItemId)
                    }
                    return
                }
                Task {
                    _ = await viewModel.retryPendingWebsite(id: pending.id)
                }
            },
            onRemove: {
                if pending.jobId != nil, pending.status != .failed {
                    Task {
                        await appEnvironment.cancelPendingWebsite(pending)
                    }
                    return
                }
                if let queueItemId = pending.queueItemId {
                    appEnvironment.removePendingQueuedWebsite(queueItemId)
                    return
                }
                viewModel.removePendingWebsite(id: pending.id)
            }
        )
    }

    var pinnedItemsSorted: [WebsiteItem] {
        let items = viewModel.panelPinnedItemsSorted
        guard !pinnedReorderDisplayedIDs.isEmpty else { return items }
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return pinnedReorderDisplayedIDs.compactMap { lookup[$0] }
    }

    var pinnedItems: [WebsiteItem] {
        viewModel.panelPinnedItemsSorted
    }

    var mainItems: [WebsiteItem] {
        viewModel.panelMainItems
    }

    var archivedItems: [WebsiteItem] {
        viewModel.panelArchivedItems
    }

    var hasArchivedContent: Bool {
        if let count = viewModel.archivedSummary?.count {
            return count > 0
        }
        return !archivedItems.isEmpty
    }

    var archivedEmptyStateText: String {
        if let count = viewModel.archivedSummary?.count {
            if count == 0 {
                return "No archived websites"
            }
        }
        if appEnvironment.isOffline || !appEnvironment.isNetworkAvailable {
            return "Archived websites are available when you're online."
        }
        return "No archived websites"
    }

    var filteredItems: [WebsiteItem] {
        viewModel.panelFilteredItems
    }

    var panelBackground: Color {
        PlatformTokens.sidebarPanelBackground
    }

    static func selectedWebsiteItem(
        for selectionID: String?,
        items: [WebsiteItem]
    ) -> WebsiteItem? {
        guard let selectionID else { return nil }
        return items.first { $0.id == selectionID }
    }

    func staggerIndex(for id: String, section: String? = nil) -> Int {
        let key = section.map { "\($0):\(id)" } ?? id
        return abs(key.hashValue % 32)
    }

    var isArchiveLoading: Bool {
        isArchiveExpanded && (viewModel.isLoadingArchived || isArchiveLoadPending)
    }

    var showArchiveLoadingPlaceholder: Bool {
        isArchiveLoading && archivedItems.isEmpty
    }

    var showArchiveEmptyState: Bool {
        !isArchiveLoading && archivedItems.isEmpty
    }

    @ViewBuilder
    func archiveLoadingRow(message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
            Text(message)
                .appFont(SidebarTypography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isCompactPhone: Bool {
        isCompact && isPhone
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private func websiteRowPrimaryAction(for item: WebsiteItem) -> (() -> Void)? {
        return { open(item: item) }
    }

    var isSaveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    saveErrorMessage = nil
                }
            }
        )
    }

    var isDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { newValue in
                if !newValue {
                    deleteTarget = nil
                }
            }
        )
    }

    func saveWebsite() {
        let raw = newWebsiteUrl.trimmed
        guard let normalized = WebsiteURLValidator.normalizedCandidate(raw) else {
            saveErrorMessage = "Enter a valid URL."
            return
        }
        newWebsiteUrl = ""
        isNewWebsitePresented = false
        Task {
            let saved = await appEnvironment.enqueueWebsiteSave(
                url: normalized.absoluteString,
                selectAfterSave: true
            )
            if saved {
                appEnvironment.notesViewModel.clearSelection()
                appEnvironment.ingestionViewModel.clearSelection()
            } else {
                saveErrorMessage = viewModel.saveErrorMessage ?? "Failed to save website. Please try again."
            }
        }
    }
}
