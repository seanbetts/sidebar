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
}

extension RefreshPlan {
    func contains(_ target: RefreshTarget) -> Bool {
        targets.contains(target)
    }

    func containsAny(_ candidates: RefreshTarget...) -> Bool {
        candidates.contains { targets.contains($0) }
    }

    func containsVisibleDetail(for section: AppSection) -> Bool {
        contains(.visibleDetail(section))
    }

    func containsListOrPinnedMetadata(for section: AppSection) -> Bool {
        containsAny(.sectionList(section), .pinnedMetadata(section))
    }

    func containsListOrVisibleDetail(for section: AppSection) -> Bool {
        containsAny(.sectionList(section), .visibleDetail(section))
    }

    func containsRefreshWork(for section: AppSection) -> Bool {
        containsAny(
            .sectionList(section),
            .visibleDetail(section),
            .pinnedMetadata(section),
            .archiveList(section)
        ) || containsGlobalRefreshWork(for: section)
    }

    private func containsGlobalRefreshWork(for section: AppSection) -> Bool {
        switch section {
        case .chat:
            return contains(.chatList)
        case .tasks:
            return contains(.taskCounts)
        case .notes, .files, .websites, .skillsStore, .settings:
            return false
        }
    }
}
