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
                            isSelected: isSelected
                        ) {
                            requestNoteSelection(id: item.id)
                        } onRename: {
                            beginRename(for: item)
                        } onDelete: {
                            confirmDelete(for: item)
                        }
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
#if !os(macOS)
            Section {
                DisclosureGroup(
                    isExpanded: $isArchiveExpanded,
                    content: {
                        if showArchiveLoadingPlaceholder {
                            archiveLoadingRow(message: "Loading archive...")
                                .padding(.leading, -DesignTokens.Spacing.sm)
                                .listRowSeparator(.hidden, edges: .top)
                        } else if showArchiveEmptyState {
                            Text(archivedEmptyStateText)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden, edges: .top)
                        } else {
                            OutlineGroup(buildItems(from: archivedNodes), children: \.children) { item in
                                NotesTreeRow(
                                    item: item,
                                    isSelected: viewModel.selectedNoteId == item.id
                                ) {
                                    if item.isFile {
                                        requestNoteSelection(id: item.id)
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                                .padding(.leading, -DesignTokens.Spacing.sm)
                                .platformContextMenu(items: noteContextMenuItemsList(for: item))
                            }
                            .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                        }
                    },
                    label: {
                        archiveLabel
                    }
                )
                .listRowBackground(
                    DesignTokens.Colors.sidebarRowBackground
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(DesignTokens.Colors.border)
                                .frame(height: 1)
                        }
                )
            }
#endif
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
                isSelected: viewModel.selectedNoteId == item.id
            ) {
                if item.isFile {
                    requestNoteSelection(id: item.id)
                }
            } onRename: {
                beginRename(for: item)
            } onDelete: {
                confirmDelete(for: item)
            }
            .platformContextMenu(items: noteContextMenuItemsList(for: item))
        }
        .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
    }

    var notesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if showArchiveLoadingPlaceholder {
                        archiveLoadingRow(message: "Loading archived notes...")
                    } else if showArchiveEmptyState {
                        Text(archivedEmptyStateText)
                            .appFont(.caption)
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
                                        requestNoteSelection(id: item.id)
                                    }
                                } onRename: {
                                    beginRename(for: item)
                                } onDelete: {
                                    confirmDelete(for: item)
                                }
                                .platformContextMenu(items: noteContextMenuItemsList(for: item))
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

    @ViewBuilder
    private func archiveLoadingRow(message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
            Text(message)
                .appFont(SidebarTypography.secondary)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var archiveLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Label("Archive", systemImage: "archivebox")
                .appFont(SidebarTypography.primary)
            if isArchiveLoading && !archivedNodes.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
            }
        }
    }

}
