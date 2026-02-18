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
        .onTapGesture {
            #if os(iOS)
            toggleQuickActions(for: item)
            #else
            open(item: item)
            #endif
        }
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

    var quickActionItem: WebsiteItem? {
        guard let quickActionWebsiteId else { return nil }
        return viewModel.items.first { $0.id == quickActionWebsiteId }
    }

    func toggleQuickActions(for item: WebsiteItem) {
        if selection == item.id {
            withAnimation {
                quickActionWebsiteId = quickActionWebsiteId == item.id ? nil : item.id
            }
            return
        }

        withAnimation {
            quickActionWebsiteId = item.id
        }
        open(item: item)
    }

    func hideQuickActions() {
        withAnimation {
            quickActionWebsiteId = nil
        }
    }

    func togglePinnedFromQuickActions(for item: WebsiteItem) {
        Task {
            await viewModel.setPinned(id: item.id, pinned: !item.pinned)
        }
    }

    func toggleArchivedFromQuickActions(for item: WebsiteItem) {
        hideQuickActions()
        Task {
            await viewModel.setArchived(id: item.id, archived: !item.archived)
        }
    }

    func promptDeleteFromQuickActions(for item: WebsiteItem) {
        hideQuickActions()
        deleteTarget = item
    }
}

struct WebsiteQuickActionsPill: View {
    let isPinned: Bool
    let isArchived: Bool
    let onPinToggle: () -> Void
    let onArchiveToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: isPinned ? "Unpin" : "Pin",
                icon: isPinned ? "pin.slash" : "pin",
                role: nil,
                action: onPinToggle
            )
            actionDivider
            actionButton(
                title: isArchived ? "Unarchive" : "Archive",
                icon: isArchived ? "archivebox.fill" : "archivebox",
                role: nil,
                action: onArchiveToggle
            )
            actionDivider
            actionButton(
                title: "Delete",
                icon: "trash",
                role: .destructive,
                action: onDelete
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .appShadow(
            color: Color.black.opacity(0.12),
            radius: DesignTokens.Spacing.sm,
            y: DesignTokens.Spacing.xs
        )
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        icon: String,
        role: ButtonRole?,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: icon)
                    .font(DesignTokens.Typography.captionSemibold)
                Text(title)
                    .font(DesignTokens.Typography.captionSemibold)
            }
            .lineLimit(1)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .foregroundStyle(
                role == .destructive ? DesignTokens.Colors.error : DesignTokens.Colors.textPrimary
            )
        }
        .buttonStyle(.plain)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 16)
    }
}
