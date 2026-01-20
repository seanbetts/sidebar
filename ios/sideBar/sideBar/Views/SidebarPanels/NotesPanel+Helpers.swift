import Foundation
import SwiftUI

// MARK: - NotesPanel+Helpers

extension NotesPanelView {
    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Notes") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newFolderName = ""
                        newFolderParent = ""
                        isNewFolderPresented = true
                    } label: {
                        Image(systemName: "folder")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add folder")
                    Button {
                        newNoteName = ""
                        isNewNotePresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add note")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $viewModel.searchQuery, placeholder: "Search notes", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var folderOptions: [NotesFolderOption] {
        NotesFolderOption.build(from: viewModel.tree?.children ?? [])
    }

    private func createNote() {
        let trimmed = newNoteName.trimmed
        guard !trimmed.isEmpty, !isCreatingNote else { return }
        isCreatingNote = true
        // Set the flag BEFORE creating the note so it's ready when currentNoteId changes
        environment.notesEditorViewModel.requestEditingOnNextLoad()
        Task {
            let created = await viewModel.createNote(title: trimmed, folder: nil)
            await MainActor.run {
                isCreatingNote = false
                if created != nil {
                    isNewNotePresented = false
                } else {
                    // Reset flag if creation failed
                    environment.notesEditorViewModel.wantsEditingOnNextLoad = false
                }
            }
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmed
        guard !trimmed.isEmpty, !isCreatingFolder else { return }
        isCreatingFolder = true
        Task {
            let destination = newFolderParent.isEmpty ? trimmed : "\(newFolderParent)/\(trimmed)"
            let created = await viewModel.createFolder(path: destination)
            await MainActor.run {
                isCreatingFolder = false
                if created {
                    isNewFolderPresented = false
                }
            }
        }
    }

    private var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { isPresented in
                if !isPresented {
                    renameTarget = nil
                    renameValue = ""
                }
            }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { isPresented in
                if !isPresented {
                    deleteTarget = nil
                }
            }
        )
    }

    private var renameDialogTitle: String {
        renameTarget?.isFile == true ? "Rename note" : "Rename folder"
    }

    private var renameDialogPlaceholder: String {
        renameTarget?.isFile == true ? "Note name" : "Folder name"
    }

    private var deleteDialogTitle: String {
        deleteTarget?.isFile == true ? "Delete note" : "Delete folder"
    }

    private var deleteDialogMessage: String {
        deleteTarget?.isFile == true
            ? "This will remove the note and cannot be undone."
            : "This will remove the folder and its contents."
    }

    private func beginRename(for item: FileNodeItem) {
        renameTarget = item
        renameValue = item.displayName
    }

    private func confirmDelete(for item: FileNodeItem) {
        deleteTarget = item
    }

    private func commitRename() {
        let target = renameTarget
        let updated = renameValue
        renameTarget = nil
        renameValue = ""
        guard let target else { return }
        Task {
            if target.isFile {
                await viewModel.renameNote(id: target.id, newName: updated)
            } else {
                await viewModel.renameFolder(path: target.id, newName: updated)
            }
        }
    }

    private func navigateNotesList(direction: ShortcutListDirection) {
        let items = noteNavigationItems()
        guard !items.isEmpty else { return }
        let currentId = viewModel.selectedNoteId
        let nextIndex: Int
        if let currentId, let index = items.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(items.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : items.count - 1
        }
        let nextId = items[nextIndex]
        Task { await viewModel.selectNote(id: nextId) }
    }

    private func noteNavigationItems() -> [String] {
        let query = viewModel.searchQuery.trimmed
        if !query.isEmpty {
            return viewModel.searchResults.map { $0.path }
        }
        let pinnedIds = pinnedItems.map { $0.id }
        let mainIds = flattenNoteIds(from: mainNodes)
        return pinnedIds + mainIds
    }

    private func flattenNoteIds(from nodes: [FileNode]) -> [String] {
        var results: [String] = []
        for node in nodes {
            if node.type == .file {
                results.append(node.path)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: flattenNoteIds(from: children))
            }
        }
        return results
    }

    private var searchResultsView: some View {
        List {
            Section("Results") {
                if let error = viewModel.errorMessage,
                   !viewModel.searchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(
                        title: "Search failed",
                        subtitle: error,
                        actionTitle: "Retry"
                    ) {
                        viewModel.updateSearch(query: viewModel.searchQuery)
                    }
                } else if viewModel.isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.searchResults.isEmpty {
                    Text("No matching notes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults, id: \.path) { node in
                        NotesTreeRow(
                            item: FileNodeItem(
                                id: node.path,
                                name: node.name,
                                type: node.type,
                                children: nil
                            ),
                            isSelected: viewModel.selectedNoteId == node.path
                        ) {
                            Task { await viewModel.selectNote(id: node.path) }
                        } onRename: {
                            beginRename(for: FileNodeItem(id: node.path, name: node.name, type: node.type, children: nil))
                        } onDelete: {
                            confirmDelete(for: FileNodeItem(id: node.path, name: node.name, type: node.type, children: nil))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
    }

    private var notesPanelContent: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmed.isEmpty {
                searchResultsView
            } else {
                notesTreeView
            }
        }
    }

    private var notesPanelContentWithArchive: some View {
        Group {
            if let error = viewModel.errorMessage, viewModel.tree == nil {
                SidebarPanelPlaceholder(
                    title: "Unable to load notes",
                    subtitle: error,
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.loadTree() }
                }
            } else if viewModel.tree == nil {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if !viewModel.searchQuery.trimmed.isEmpty {
                searchResultsView
            } else {
                VStack(spacing: 0) {
                    notesTreeListView
                    notesArchiveSection
                }
            }
        }
    }

    private func buildItems(from nodes: [FileNode]) -> [FileNodeItem] {
        nodes.map { node in
            let children = node.type == .directory ? buildItems(from: node.children ?? []) : nil
            return FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: children
            )
        }
    }

    private var notesTreeListView: some View {
        List {
            Section("Pinned") {
                if pinnedItems.isEmpty {
                    Text("No pinned notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinnedItems) { item in
                        NotesTreeRow(
                            item: item,
                            isSelected: viewModel.selectedNoteId == item.id
                        ) {
                            Task { await viewModel.selectNote(id: item.id) }
                        } onRename: {
                            beginRename(for: item)
                        } onDelete: {
                            confirmDelete(for: item)
                        }
                    }
                }
            }

            Section("Notes") {
                mainOutlineGroup
            }
#if !os(macOS)
            Section {
                DisclosureGroup(
                    isExpanded: $isArchiveExpanded,
                    content: {
                        if archivedNodes.isEmpty {
                            Text("No archived notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                                NotesTreeRow(
                                    item: item,
                                    isSelected: viewModel.selectedNoteId == item.id
                                ) {
                                    if item.isFile {
                                        Task { await viewModel.selectNote(id: item.id) }
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                            }
                            .listRowBackground(rowBackground)
                        }
                    },
                    label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                )
                .listRowBackground(rowBackground)
            }
#endif
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.loadTree()
        }
    }

    private var notesTreeView: some View {
        notesTreeListView
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var mainOutlineGroup: some View {
        OutlineGroup(buildItems(from: mainNodes), children: \.children) { item in
            NotesTreeRow(
                item: item,
                isSelected: viewModel.selectedNoteId == item.id
            ) {
                if item.isFile {
                    Task { await viewModel.selectNote(id: item.id) }
                }
            } onRename: {
                beginRename(for: item)
            } onDelete: {
                confirmDelete(for: item)
            }
        }
        .listRowBackground(rowBackground)
    }

    private var notesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if archivedNodes.isEmpty {
                        Text("No archived notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                                NotesTreeRow(
                                    item: item,
                                    isSelected: viewModel.selectedNoteId == item.id,
                                    useListStyling: false
                                ) {
                                    if item.isFile {
                                        Task { await viewModel.selectNote(id: item.id) }
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                            }
                        }
                        .frame(maxHeight: 650)
                    }
                },
                label: {
                    Label("Archive", systemImage: "archivebox")
                        .font(.subheadline)
                }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(panelBackground)
    }

    private var pinnedItems: [FileNodeItem] {
        let pinned = collectPinnedNodes(from: viewModel.tree?.children ?? [])
        let sorted = pinned.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return sorted.map { node in
            FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: nil
            )
        }
    }

    private var mainNodes: [FileNode] {
        filterNodes(viewModel.tree?.children ?? [], includeArchived: false)
    }

    private var archivedNodes: [FileNode] {
        let nodes = filterNodes(viewModel.tree?.children ?? [], includeArchived: true)
        return normalizeArchivedNodes(nodes)
    }

    private func normalizeArchivedNodes(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in
            if node.type == .directory, node.name.lowercased() == "archive" {
                return node.children ?? []
            }
            return [node]
        }
    }

    private func collectPinnedNodes(from nodes: [FileNode]) -> [FileNode] {
        var results: [FileNode] = []
        for node in nodes {
            if node.type == .file, node.pinned == true, node.archived != true {
                results.append(node)
            }
            if let children = node.children, !children.isEmpty {
                results.append(contentsOf: collectPinnedNodes(from: children))
            }
        }
        return results
    }

    private func filterNodes(_ nodes: [FileNode], includeArchived: Bool) -> [FileNode] {
        nodes.compactMap { node in
            if node.type == .directory {
                let children = filterNodes(node.children ?? [], includeArchived: includeArchived)
                if !includeArchived && node.name.lowercased() == "archive" {
                    return nil
                }
                return FileNode(
                    name: node.name,
                    path: node.path,
                    type: node.type,
                    size: node.size,
                    modified: node.modified,
                    children: children,
                    expanded: node.expanded,
                    pinned: node.pinned,
                    pinnedOrder: node.pinnedOrder,
                    archived: node.archived,
                    folderMarker: node.folderMarker
                )
            }
            let archived = node.archived == true
            let pinned = node.pinned == true
            if includeArchived {
                return archived ? node : nil
            }
            return (!archived && !pinned) ? node : nil
        }
    }
}


}
