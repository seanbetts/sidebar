import Foundation
import sideBarShared
import SwiftUI

// MARK: - NotesPanel+TreeArchive

extension NotesPanelView {
    func buildItems(from nodes: [FileNode]) -> [FileNodeItem] {
        nodes.map { node in
            let children = node.type == .directory ? buildItems(from: node.children ?? []) : nil
            return FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: children,
                pinned: node.pinned ?? false,
                archived: node.archived ?? false,
                created: node.created
            )
        }
    }

    var notesTreeListView: some View {
        List {
            switch panelState {
            case .sparse:
                Section {
                    SidebarSparseStateRow(
                        iconName: "note.text",
                        title: Self.sparseStateTitle,
                        subtitle: Self.sparseStateSubtitle
                    )
                }
            case .content:
                Section {
                    if pinnedItems.isEmpty {
                        Text("No pinned notes")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                    } else {
                        ForEach(pinnedItems) { item in
                            let isSelected = viewModel.selectedNoteId == item.id
                            NotesTreeRow(
                                item: item,
                                isSelected: isSelected,
                                onSelect: {
                                    requestNoteSelection(id: item.id)
                                },
                                onRename: nil,
                                onDelete: {
                                    confirmDelete(for: item)
                                }
                            )
                            .platformContextMenu(items: noteContextMenuItemsList(for: item))
                            .listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected: isSelected))
                        }
                    }
                } header: {
                    sidebarProminentSectionHeader("Pinned")
                }
                .listRowBackground(DesignTokens.Colors.sidebarRowBackground)

                Section {
                    mainOutlineGroup
                } header: {
                    sidebarProminentSectionHeader("Notes")
                }
            case .loading, .error, .search:
                EmptyView()
            }
            Section {
                SelectableRow(
                    isSelected: false,
                    insets: EdgeInsets(
                        top: DesignTokens.Spacing.xxl,
                        leading: archiveRowHorizontalInset,
                        bottom: 0,
                        trailing: archiveRowHorizontalInset
                    )
                ) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Label("Archive", systemImage: "archivebox")
                            .appFont(SidebarTypography.primary)
                        Spacer()
                        if isArchiveLoading && !archivedNodes.isEmpty {
                            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                        }
                        Image(systemName: isArchiveExpanded ? "chevron.down" : "chevron.right")
                            .appFont(SidebarTypography.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                .onTapGesture {
                    isArchiveExpanded.toggle()
                }

                if isArchiveExpanded {
                    if showArchiveLoadingPlaceholder {
                        SelectableRow(isSelected: false) {
                            archiveLoadingRow(message: "Loading archive...")
                        }
                    } else if showArchiveEmptyState {
                        SelectableRow(isSelected: false) {
                            Text(archivedEmptyStateText)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                            NotesTreeRow(
                                item: item,
                                isSelected: viewModel.selectedNoteId == item.id,
                                onSelect: {
                                    if item.isFile {
                                        requestNoteSelection(id: item.id)
                                    }
                                },
                                onRename: item.isFile ? nil : { beginRename(for: item) },
                                onDelete: {
                                    confirmDelete(for: item)
                                }
                            )
                            .platformContextMenu(items: noteContextMenuItemsList(for: item))
                        }
                        .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                    }
                }
            }
        }
        .sidebarPanelListStyle()
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.loadTree()
        }
    }

    var notesTreeView: some View {
        notesTreeListView
    }

    var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    var mainOutlineGroup: some View {
        OutlineGroup(buildItems(from: mainNodes), children: \.children) { item in
            NotesTreeRow(
                item: item,
                isSelected: viewModel.selectedNoteId == item.id,
                onSelect: {
                    if item.isFile {
                        requestNoteSelection(id: item.id)
                    }
                },
                onRename: item.isFile ? nil : { beginRename(for: item) },
                onDelete: {
                    confirmDelete(for: item)
                }
            )
            .platformContextMenu(items: noteContextMenuItemsList(for: item))
        }
        .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
    }

    @ViewBuilder
    private func archiveLoadingRow(message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
            Text(message)
                .appFont(SidebarTypography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private var archiveRowHorizontalInset: CGFloat {
        #if os(macOS)
        return DesignTokens.Spacing.sm
        #else
        return DesignTokens.Spacing.smPlus
        #endif
    }

}
