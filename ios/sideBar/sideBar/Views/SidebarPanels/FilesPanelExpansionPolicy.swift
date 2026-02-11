import Foundation
import sideBarShared

enum FilesPanelExpansionPolicy {
    static func shouldInitializeBaseline(
        isLoading: Bool,
        awaitingInitialLoad: Bool,
        hasBaseline: Bool
    ) -> Bool {
        !isLoading && !awaitingInitialLoad && !hasBaseline
    }

    static func currentFileIds(from items: [IngestionListItem]) -> Set<String> {
        Set(items.map { $0.file.id })
    }

    static func shouldAutoExpandVideo(
        hasBaseline: Bool,
        previousKnownFileIds: Set<String>,
        items: [IngestionListItem]
    ) -> Bool {
        guard hasBaseline else { return false }
        return items.contains { item in
            !previousKnownFileIds.contains(item.file.id)
                && item.file.mimeOriginal.localizedCaseInsensitiveContains("youtube")
        }
    }
}
