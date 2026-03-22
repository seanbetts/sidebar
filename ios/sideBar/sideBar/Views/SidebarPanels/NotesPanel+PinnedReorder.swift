import Foundation
import Combine
import sideBarShared
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class NotesPanelPinnedReorderState: ObservableObject {
    @Published var isReordering = false
    @Published var sourceID: String?
    @Published var snapshotIDs: [String] = []
}

extension NotesPanelView {
    enum PinnedReorderSection: Equatable {
        case pinned
        case mainNotes
        case archive
    }

    var canStartPinnedReorder: Bool {
        pinnedReorderCanInteract && !isPinnedReordering
    }

    var isPinnedReorderActive: Bool {
        isPinnedReordering
    }

    var isPinnedReordering: Bool {
        pinnedReorderState.isReordering
    }

    var pinnedReorderSourceID: String? {
        pinnedReorderState.sourceID
    }

    func enterPinnedReorder(from sourceID: String) {
        guard canStartPinnedReorder else { return }
        pinnedReorderState.isReordering = true
        pinnedReorderState.sourceID = sourceID
        pinnedReorderState.snapshotIDs = pinnedItems.map(\.id)
    }

    func completePinnedReorder() {
        pinnedReorderState.isReordering = false
        pinnedReorderState.sourceID = nil
        pinnedReorderState.snapshotIDs = []
    }

    func cancelPinnedReorder() {
        completePinnedReorder()
    }

    func handlePinnedSetChanged(_ pinnedIDs: [String]) {
        guard isPinnedReordering else { return }
        guard pinnedIDs != pinnedReorderState.snapshotIDs else { return }
        cancelPinnedReorder()
    }

    func reorderedPinnedIDs(from source: IndexSet, to destination: Int) -> [String] {
        var ids = pinnedItems.map(\.id)
        guard !source.isEmpty else { return ids }
        let movingIDs = source.compactMap { index -> String? in
            guard ids.indices.contains(index) else { return nil }
            return ids[index]
        }
        ids.remove(atOffsets: source)
        let insertIndex = min(max(destination, 0), ids.count)
        ids.insert(contentsOf: movingIDs, at: insertIndex)
        return ids
    }

    func reorderedPinnedIDs(moving sourceID: String, to destinationID: String?) -> [String] {
        var ids = pinnedItems.map(\.id)
        guard let sourceIndex = ids.firstIndex(of: sourceID) else { return ids }
        ids.remove(at: sourceIndex)
        guard let destinationID, let destinationIndex = ids.firstIndex(of: destinationID) else {
            ids.append(sourceID)
            return ids
        }
        ids.insert(sourceID, at: destinationIndex)
        return ids
    }

    func movePinnedNotes(from source: IndexSet, to destination: Int) {
        guard isPinnedReordering else { return }
        let reorderedIDs = reorderedPinnedIDs(from: source, to: destination)
        Task { @MainActor in
            _ = await viewModel.reorderPinnedNotes(ids: reorderedIDs)
            completePinnedReorder()
        }
    }

    func performPinnedDrop(sourceID: String, destinationID: String) {
        guard isPinnedReordering || pinnedReorderCanInteract else { return }
        let reorderedIDs = reorderedPinnedIDs(moving: sourceID, to: destinationID)
        Task { @MainActor in
            _ = await viewModel.reorderPinnedNotes(ids: reorderedIDs)
            completePinnedReorder()
        }
    }

    func canAcceptPinnedDrop(
        isPinned: Bool,
        sourceSection: PinnedReorderSection,
        destinationSection: PinnedReorderSection
    ) -> Bool {
        isPinned && sourceSection == .pinned && destinationSection == .pinned
    }

    @ViewBuilder
    func pinnedNotesSection() -> some View {
        if pinnedItems.isEmpty {
            Text("No pinned notes")
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
        } else {
            #if os(iOS)
            ForEach(pinnedItems) { item in
                pinnedNoteRow(item: item)
            }
            .onMove(perform: movePinnedNotes)
            .environment(\.editMode, .constant(isPinnedReordering ? .active : .inactive))
            #else
            ForEach(pinnedItems) { item in
                pinnedNoteRow(item: item)
            }
            #endif
        }
    }

    @ViewBuilder
    func pinnedNoteRow(item: FileNodeItem) -> some View {
        let isSelected = viewModel.selectedNoteId == item.id
        let row = NotesTreeRow(
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

        #if os(iOS)
        row
            .contentShape(Rectangle())
            .onLongPressGesture {
                enterPinnedReorder(from: item.id)
            }
        #elseif os(macOS)
        if pinnedReorderCanInteract || isPinnedReordering {
            row
                .onDrag {
                    enterPinnedReorder(from: item.id)
                    return NSItemProvider(object: item.id as NSString)
                }
                .dropDestination(for: String.self) { sourceIDs, _ in
                    guard let sourceID = sourceIDs.first else { return false }
                    guard canAcceptPinnedDrop(
                        isPinned: true,
                        sourceSection: .pinned,
                        destinationSection: .pinned
                    ) else {
                        return false
                    }
                    guard sourceID != item.id else { return false }
                    performPinnedDrop(sourceID: sourceID, destinationID: item.id)
                    return true
                }
        } else {
            row
        }
        #else
        row
        #endif
    }

    private var pinnedReorderCanInteract: Bool {
        pinnedReorderNetworkIsAvailable && pinnedItems.count > 1
    }

    private var pinnedReorderNetworkIsAvailable: Bool {
        pinnedReorderNetworkAvailabilityOverride
            ?? (environment.isNetworkAvailable && !environment.isOffline)
    }
}
