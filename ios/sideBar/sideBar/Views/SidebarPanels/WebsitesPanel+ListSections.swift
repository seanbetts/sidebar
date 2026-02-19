import Foundation
import sideBarShared
import SwiftUI

extension WebsitesPanelView {
    func open(item: WebsiteItem) {
        selection = item.id
        Task { await viewModel.selectWebsite(id: item.id) }
    }

    func navigateWebsitesList(direction: ShortcutListDirection) {
        let ids = websitesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = selection ?? viewModel.active?.id
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
        allowArchive: Bool = true
    ) -> some View {
        let isSelected = selection == item.id
        let row = WebsiteRow(
            item: item,
            isSelected: isSelected,
            useListStyling: useListStyling,
            faviconBaseUrl: appEnvironment.container.config.r2Endpoint,
            r2FaviconBucket: appEnvironment.container.config.r2FaviconBucket,
            r2FaviconPublicBaseUrl: appEnvironment.container.config.r2FaviconPublicBaseUrl
        )
        .staggeredAppear(index: index, isActive: listAppeared)
        .onTapGesture { open(item: item) }
        .platformContextMenu(items: websiteContextMenuItemsList(for: item))
        .listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected: isSelected))

        #if os(macOS)
        row
        #else
        row
            .sidebarListSwipeActions(
                leadingTitle: allowArchive ? "Archive" : "Unarchive",
                leadingSystemImage: allowArchive ? "archivebox" : "tray.and.arrow.up",
                onLeading: {
                    Task { await viewModel.setArchived(id: item.id, archived: allowArchive) }
                },
                onDelete: {
                    deleteTarget = item
                }
            )
        #endif
    }

    var pinnedItemsSorted: [WebsiteItem] {
        viewModel.panelPinnedItemsSorted
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
        DesignTokens.Colors.sidebar
    }

    var websitesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if showArchiveLoadingPlaceholder {
                        archiveLoadingRow(message: "Loading archived websites...")
                    } else if showArchiveEmptyState {
                        Text(archivedEmptyStateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                                ForEach(archivedItems, id: \.id) { item in
                                    let index = staggerIndex(for: item.id, section: "archive")
                                    websiteListRow(item: item, index: index, useListStyling: false, allowArchive: false)
                                }
                            }
                        }
                        .frame(maxHeight: 650)
                    }
                },
                label: {
                    archiveLabel
                }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(panelBackground)
    }

    func staggerIndex(for id: String, section: String? = nil) -> Int {
        let key = section.map { "\($0):\(id)" } ?? id
        return abs(key.hashValue % 32)
    }

    var isArchiveLoading: Bool {
        isArchiveExpanded && viewModel.isLoadingArchived
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var archiveLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Label("Archive", systemImage: "archivebox")
                .font(.subheadline)
            if isArchiveLoading && !archivedItems.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
            }
        }
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
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
            let saved = await viewModel.saveWebsite(url: normalized.absoluteString)
            if saved {
                appEnvironment.notesViewModel.clearSelection()
                appEnvironment.ingestionViewModel.clearSelection()
            } else {
                saveErrorMessage = viewModel.saveErrorMessage ?? "Failed to save website. Please try again."
            }
        }
    }
}
