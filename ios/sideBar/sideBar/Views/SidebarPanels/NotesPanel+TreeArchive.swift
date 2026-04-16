import Foundation
import sideBarShared
import SwiftUI

// MARK: - NotesPanel+TreeArchive

extension NotesPanelView {
    func buildItems(from nodes: [FileNode], depth: Int = 0) -> [FileNodeItem] {
        nodes.map { node in
            let children = node.type == .directory
                ? buildItems(from: node.children ?? [], depth: depth + 1)
                : nil
            return FileNodeItem(
                id: node.path,
                name: node.name,
                type: node.type,
                children: children,
                pinned: node.pinned ?? false,
                archived: node.archived ?? false,
                created: node.created,
                depth: depth
            )
        }
    }

    var notesTreeListView: some View {
        notesPanelList {
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
                if listSectionLayout.contains(.pinned) {
                    Section {
                        pinnedNotesSection()
                    } header: {
                        sidebarProminentSectionHeader("Pinned")
                    }
                    .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                }

                Section {
                    notesTreeRows(buildItems(from: mainNodes))
                } header: {
                    sidebarProminentSectionHeader("Notes")
                }
            case .loading, .error, .search, .empty:
                EmptyView()
            }
            if listSectionLayout.contains(.archive) {
                Section {
                    SelectableRow(
                        isSelected: false,
                        insets: EdgeInsets(
                            top: 0,
                            leading: archiveRowHorizontalInset,
                            bottom: 0,
                            trailing: archiveRowHorizontalInset
                        ),
                        primaryAction: {
                            isArchiveExpanded.toggle()
                        },
                        content: {
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
                    )

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
                            notesTreeRows(buildItems(from: archivedNodes))
                        }
                    }
                } header: {
                    sidebarSectionSpacerHeader()
                }
            }
        }
        .sidebarPanelListStyle(reducesCompactPhoneSectionHeaderGap: isCompactPhone)
        .sidebarCompactPhoneTopPadding(
            LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,
            isCompactPhone: isCompactPhone
        )
        #if os(iOS)
        .environment(\.editMode, .constant(isPinnedReorderEditActive ? .active : .inactive))
        #endif
        .scrollContentBackground(.hidden)
        .sidebarPanelListBackground()
        .refreshable {
            await viewModel.loadTree()
        }
        .onChange(of: pinnedItems.map(\.id)) { _, newValue in
            handlePinnedSetChanged(newValue)
        }
    }

    var notesTreeView: some View {
        notesTreeListView
    }

    var panelBackground: Color {
        PlatformTokens.sidebarPanelBackground
    }

    @ViewBuilder
    func notesTreeRows(_ items: [FileNodeItem]) -> some View {
        ForEach(Self.visibleItems(from: items, expandedFolderIDs: expandedFolderIDs), id: \.id) { item in
            let row = NotesTreeRow(
                item: item,
                isSelected: viewModel.selectedNoteId == item.id,
                isExpanded: item.isFile ? nil : expandedFolderIDs.contains(item.id),
                onSelect: {
                    if item.isFile {
                        requestNoteSelection(id: item.id)
                    } else {
                        toggleFolderExpansion(item.id)
                    }
                },
                onRename: { beginRename(for: item) },
                onDelete: {
                    confirmDelete(for: item)
                }
            )
            .platformContextMenu(items: noteContextMenuItemsList(for: item))
            row
        }
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
