import Foundation

enum DomainSyncChangeKind: Equatable {
    case metadataPatch
    case listRefresh
    case detailRefresh
    case archiveRefresh
    case jobProgress
    case ignored
}

struct DomainSyncChange: Equatable {
    let section: AppSection
    let entityId: String?
    let kind: DomainSyncChangeKind
    let updatedAt: Date?
    let requiresListRefresh: Bool
    let requiresDetailRefresh: Bool
    let canPatchMetadata: Bool

    var refreshTargets: [RefreshTarget] {
        var targets: [RefreshTarget] = []
        if requiresListRefresh {
            targets.append(.sectionList(section))
        }
        if requiresDetailRefresh {
            targets.append(.visibleDetail(section))
        }
        if kind == .archiveRefresh {
            targets.append(.archiveList(section))
        }
        return targets
    }
}
