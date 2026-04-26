import Foundation

enum RefreshTrigger: String, Equatable {
    case coldLaunch
    case warmForeground
    case reconnect
    case visibleSectionChanged
    case manualRefresh
}

enum RefreshTarget: Hashable, Equatable {
    case chatList
    case taskCounts
    case sectionList(AppSection)
    case visibleDetail(AppSection)
    case pinnedMetadata(AppSection)
    case archiveList(AppSection)

    var traceName: String {
        switch self {
        case .chatList:
            return "chatList"
        case .taskCounts:
            return "taskCounts"
        case .sectionList(let section):
            return "sectionList.\(section.rawValue)"
        case .visibleDetail(let section):
            return "visibleDetail.\(section.rawValue)"
        case .pinnedMetadata(let section):
            return "pinnedMetadata.\(section.rawValue)"
        case .archiveList(let section):
            return "archiveList.\(section.rawValue)"
        }
    }
}

struct RefreshContext: Equatable {
    let visibleSection: AppSection?
    let hasVisibleDetail: Bool
    let pinnedSections: [AppSection]
    let lastOpenedSection: AppSection?
    let staleTargets: [RefreshTarget]
    let canAttemptServerRead: Bool
}

struct RefreshPlan: Hashable, Equatable {
    let trigger: RefreshTrigger
    let targets: [RefreshTarget]
    let requiresQueueReplayFirst: Bool

    var traceTargets: String {
        targets.map(\.traceName).joined(separator: ",")
    }
}
