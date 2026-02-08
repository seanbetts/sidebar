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
        if !searchQuery.trimmed.isEmpty {
            return filteredItems.map { $0.id }
        }
        return pinnedItemsSorted.map { $0.id } + mainItems.map { $0.id }
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
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if allowArchive {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: true) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.blue)
                } else {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: false) }
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteTarget = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        #endif
    }

    var pinnedItemsSorted: [WebsiteItem] {
        pinnedItems.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    var pinnedItems: [WebsiteItem] {
        viewModel.items.filter { $0.pinned && !$0.archived }
    }

    var mainItems: [WebsiteItem] {
        viewModel.items.filter { !$0.pinned && !$0.archived }
    }

    var archivedItems: [WebsiteItem] {
        viewModel.items.filter { $0.archived }
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
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.title.lowercased().contains(needle) ||
            item.domain.lowercased().contains(needle) ||
            item.url.lowercased().contains(needle)
        }
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
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
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
            ProgressView()
                .controlSize(.small)
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
                ProgressView()
                    .controlSize(.small)
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
