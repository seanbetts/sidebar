import Combine
import Foundation
import sideBarShared
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class WebsitesPanelPinnedReorderState: ObservableObject {
    @Published var isReordering = false
    @Published var sourceID: String?
    @Published var snapshotIDs: [String] = []
}

extension WebsitesPanelView {
    enum PinnedReorderSection: Equatable {
        case pinned
        case mainWebsites
        case archive
    }

    var canStartPinnedReorder: Bool {
        pinnedReorderCanInteract && !isPinnedReordering
    }

    var isPinnedReordering: Bool {
        pinnedReorderState.isReordering
    }

    var pinnedReorderSourceID: String? {
        pinnedReorderState.sourceID
    }

    var pinnedReorderEditMode: EditMode {
        isPinnedReordering ? .active : .inactive
    }

    func enterPinnedReorder(from sourceID: String) {
        guard canStartPinnedReorder else { return }
        pinnedReorderState.isReordering = true
        pinnedReorderState.sourceID = sourceID
        pinnedReorderState.snapshotIDs = pinnedItemsSorted.map(\.id)
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
        var ids = pinnedItemsSorted.map(\.id)
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
        var ids = pinnedItemsSorted.map(\.id)
        guard let sourceIndex = ids.firstIndex(of: sourceID) else { return ids }
        ids.remove(at: sourceIndex)
        guard let destinationID, let destinationIndex = ids.firstIndex(of: destinationID) else {
            ids.append(sourceID)
            return ids
        }
        ids.insert(sourceID, at: destinationIndex)
        return ids
    }

    func movePinnedWebsites(from source: IndexSet, to destination: Int) {
        guard isPinnedReordering else { return }
        let reorderedIDs = reorderedPinnedIDs(from: source, to: destination)
        Task { @MainActor in
            _ = await viewModel.reorderPinnedWebsites(ids: reorderedIDs)
            completePinnedReorder()
        }
    }

    func performPinnedDrop(sourceID: String, destinationID: String) {
        guard isPinnedReordering || pinnedReorderCanInteract else { return }
        let reorderedIDs = reorderedPinnedIDs(moving: sourceID, to: destinationID)
        Task { @MainActor in
            _ = await viewModel.reorderPinnedWebsites(ids: reorderedIDs)
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
    func pinnedWebsitesSection() -> some View {
        if pinnedItemsSorted.isEmpty {
            EmptyView()
        } else {
            #if os(iOS)
            ForEach(pinnedItemsSorted, id: \.id) { item in
                pinnedWebsiteRow(item: item)
            }
            .onMove(perform: movePinnedWebsites)
            #else
            ForEach(pinnedItemsSorted, id: \.id) { item in
                pinnedWebsiteRow(item: item)
            }
            #endif
        }
    }

    @ViewBuilder
    func pinnedWebsiteRow(item: WebsiteItem) -> some View {
        let row = websiteListRow(
            item: item,
            index: staggerIndex(for: item.id, section: "pinned"),
            allowArchive: true
        )

        #if os(iOS)
        row
        #elseif os(macOS)
        if pinnedReorderCanInteract || isPinnedReordering {
            row
                .onDrag {
                    enterPinnedReorder(from: item.id)
                    return NSItemProvider(object: item.id as NSString)
                }
                .dropDestination(for: String.self) { sourceIDs, _ in
                    guard let sourceID = sourceIDs.first else { return false }
                    guard sourceID != item.id else { return false }
                    guard canAcceptPinnedDrop(
                        isPinned: true,
                        sourceSection: .pinned,
                        destinationSection: .pinned
                    ) else {
                        return false
                    }
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
        pinnedReorderNetworkIsAvailable && pinnedItemsSorted.count > 1
    }

    private var pinnedReorderNetworkIsAvailable: Bool {
        pinnedReorderNetworkAvailabilityOverride
            ?? (appEnvironment.isNetworkAvailable && !appEnvironment.isOffline)
    }
}
