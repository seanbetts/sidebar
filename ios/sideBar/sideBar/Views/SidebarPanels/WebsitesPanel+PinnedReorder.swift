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
    @Published var isPersisting = false
    @Published var sourceID: String?
    @Published var snapshotIDs: [String] = []
    @Published var displayedIDs: [String] = []
    var autoExitTask: Task<Void, Never>?
}

extension WebsitesPanelView {
    enum PinnedReorderSection: Equatable {
        case pinned
        case mainWebsites
        case archive
    }

    var canStartPinnedReorder: Bool {
        pinnedReorderCanInteract && !isPinnedReordering && !isPinnedReorderPersisting
    }

    var isPinnedReordering: Bool {
        pinnedReorderState.isReordering
    }

    var pinnedReorderSourceID: String? {
        pinnedReorderState.sourceID
    }

    var pinnedReorderDisplayedIDs: [String] {
        pinnedReorderState.displayedIDs
    }

    var isPinnedReorderPersisting: Bool {
        pinnedReorderState.isPersisting
    }

    var isPinnedReorderEditActive: Bool {
        pinnedReorderCanInteract || isPinnedReordering
    }

    func enterPinnedReorder(from sourceID: String) {
        guard canStartPinnedReorder else { return }
        pinnedReorderState.isReordering = true
        pinnedReorderState.sourceID = sourceID
        pinnedReorderState.snapshotIDs = pinnedItemsSorted.map(\.id)
        pinnedReorderState.displayedIDs = pinnedReorderState.snapshotIDs
        schedulePinnedReorderAutoExit()
    }

    func completePinnedReorder() {
        pinnedReorderState.autoExitTask?.cancel()
        pinnedReorderState.autoExitTask = nil
        pinnedReorderState.isReordering = false
        pinnedReorderState.isPersisting = false
        pinnedReorderState.sourceID = nil
        pinnedReorderState.snapshotIDs = []
        pinnedReorderState.displayedIDs = []
    }

    func cancelPinnedReorder() {
        completePinnedReorder()
    }

    func handlePinnedSetChanged(_ pinnedIDs: [String]) {
        guard isPinnedReordering || isPinnedReorderPersisting else { return }
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
        #if os(iOS)
        guard pinnedReorderCanInteract else { return }
        let reorderedIDs = reorderedPinnedIDs(from: source, to: destination)
        Task {
            if await viewModel.reorderPinnedWebsites(ids: reorderedIDs) {
                Haptics.notification(.success)
            }
        }
        #else
        guard isPinnedReordering else { return }
        let reorderedIDs = reorderedPinnedIDs(from: source, to: destination)
        pinnedReorderState.displayedIDs = reorderedIDs
        schedulePinnedReorderAutoExit()
        #endif
    }

    func performPinnedDrop(sourceID: String, destinationID: String) {
        guard isPinnedReordering || pinnedReorderCanInteract else { return }
        let reorderedIDs = reorderedPinnedIDs(moving: sourceID, to: destinationID)
        pinnedReorderState.displayedIDs = reorderedIDs
        schedulePinnedReorderAutoExit()
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

    private var pinnedReorderAutoExitDelay: TimeInterval {
        pinnedReorderAutoExitDelayOverride ?? 4
    }

    private var pinnedReorderNetworkIsAvailable: Bool {
        pinnedReorderNetworkAvailabilityOverride
            ?? (appEnvironment.isNetworkAvailable && !appEnvironment.isOffline)
    }

    private func schedulePinnedReorderAutoExit() {
        #if os(iOS)
        return
        #else
        pinnedReorderState.autoExitTask?.cancel()
        let delay = pinnedReorderAutoExitDelay
        pinnedReorderState.autoExitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await commitPinnedReorderIfNeeded()
        }
        #endif
    }

    private func commitPinnedReorderIfNeeded() async {
        #if os(iOS)
        return
        #else
        guard isPinnedReordering else { return }
        pinnedReorderState.autoExitTask?.cancel()
        pinnedReorderState.autoExitTask = nil

        let snapshotIDs = pinnedReorderState.snapshotIDs
        let finalIDs = pinnedReorderState.displayedIDs.isEmpty ? snapshotIDs : pinnedReorderState.displayedIDs

        pinnedReorderState.isReordering = false
        pinnedReorderState.sourceID = nil

        guard finalIDs != snapshotIDs else {
            completePinnedReorder()
            return
        }

        pinnedReorderState.isPersisting = true
        if await viewModel.reorderPinnedWebsites(ids: finalIDs) {
            Haptics.notification(.success)
        }
        completePinnedReorder()
        #endif
    }
}
