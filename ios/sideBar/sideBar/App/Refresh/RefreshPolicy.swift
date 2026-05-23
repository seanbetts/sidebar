import Foundation

@MainActor
struct RefreshPolicy {
    let metadataStore: RefreshMetadataStore?
    private let now: () -> Date

    init(
        metadataStore: RefreshMetadataStore? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.metadataStore = metadataStore
        self.now = now
    }

    func makePlan(trigger: RefreshTrigger, context: RefreshContext) -> RefreshPlan {
        switch trigger {
        case .coldLaunch:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(
                    baseTargets(for: context, includeLastOpenedSection: true, staleOnly: false)
                ),
                requiresQueueReplayFirst: false
            )
        case .warmForeground:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(
                    resolvedStaleTargets(
                        for: trigger,
                        context: context,
                        candidates: foregroundTargets(for: context)
                    )
                ),
                requiresQueueReplayFirst: false
            )
        case .reconnect:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(
                    baseTargets(for: context, includeLastOpenedSection: false, staleOnly: false)
                ),
                requiresQueueReplayFirst: true
            )
        case .visibleSectionChanged, .manualRefresh:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(
                    resolvedStaleTargets(
                        for: trigger,
                        context: context,
                        candidates: visibleTargets(for: context)
                    )
                ),
                requiresQueueReplayFirst: false
            )
        case .realtimeInvalidation:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(realtimeTargets(from: context.staleTargets)),
                requiresQueueReplayFirst: false
            )
        case .jobTerminalState, .decodeFailure:
            return RefreshPlan(
                trigger: trigger,
                targets: dedupedTargets(context.staleTargets),
                requiresQueueReplayFirst: false
            )
        }
    }

    private func baseTargets(
        for context: RefreshContext,
        includeLastOpenedSection: Bool,
        staleOnly: Bool
    ) -> [RefreshTarget] {
        var targets: [RefreshTarget] = [.chatList, .taskCounts]
        targets.append(contentsOf: visibleTargets(for: context))

        if includeLastOpenedSection,
           let lastOpenedSection = context.lastOpenedSection,
           lastOpenedSection != context.visibleSection {
            targets.append(.sectionList(lastOpenedSection))
        }

        targets.append(contentsOf: context.pinnedSections.map { .pinnedMetadata($0) })
        if staleOnly {
            return targets.filter(context.staleTargets.contains)
        }
        return targets
    }

    private func visibleTargets(for context: RefreshContext) -> [RefreshTarget] {
        guard let visibleSection = context.visibleSection else { return [] }
        var targets = sectionTargets(for: visibleSection)
        if context.hasVisibleDetail {
            targets.append(.visibleDetail(visibleSection))
        }
        return targets
    }

    private func sectionTargets(for section: AppSection) -> [RefreshTarget] {
        switch section {
        case .chat:
            return [.chatList]
        case .tasks:
            return [.sectionList(.tasks), .taskCounts]
        default:
            return [.sectionList(section)]
        }
    }

    private func foregroundTargets(for context: RefreshContext) -> [RefreshTarget] {
        var targets: [RefreshTarget] = [.chatList, .taskCounts]
        targets.append(contentsOf: visibleTargets(for: context))
        targets.append(contentsOf: context.pinnedSections.map { .pinnedMetadata($0) })
        return targets
    }

    private func realtimeTargets(from staleTargets: [RefreshTarget]) -> [RefreshTarget] {
        var targets: [RefreshTarget] = []
        for target in staleTargets {
            targets.append(target)
            if target == .sectionList(.tasks) {
                targets.append(.taskCounts)
            }
        }
        return targets
    }

    private func resolvedStaleTargets(
        for trigger: RefreshTrigger,
        context: RefreshContext,
        candidates: [RefreshTarget]
    ) -> [RefreshTarget] {
        if trigger == .manualRefresh {
            return candidates
        }

        let metadataStaleTargets: [RefreshTarget]
        if let metadataStore {
            metadataStaleTargets = candidates.filter { target in
                metadataStore.isStale(
                    target,
                    maxAge: staleWindow(for: trigger, target: target),
                    now: now()
                )
            }
        } else {
            metadataStaleTargets = []
        }

        let explicitStaleTargets = Set(context.staleTargets)
        let metadataTargets = Set(metadataStaleTargets)
        return candidates.filter { explicitStaleTargets.contains($0) || metadataTargets.contains($0) }
    }

    private func staleWindow(for trigger: RefreshTrigger, target: RefreshTarget) -> TimeInterval {
        switch trigger {
        case .warmForeground:
            return warmForegroundWindow(for: target)
        case .visibleSectionChanged:
            return visibleSectionWindow(for: target)
        case .manualRefresh, .realtimeInvalidation, .jobTerminalState, .decodeFailure:
            return 0
        case .coldLaunch, .reconnect:
            return 0
        }
    }

    private func warmForegroundWindow(for target: RefreshTarget) -> TimeInterval {
        switch target {
        case .chatList:
            return 120
        case .taskCounts:
            return 60
        case .sectionList:
            return 120
        case .visibleDetail:
            return 180
        case .pinnedMetadata:
            return 300
        case .archiveList:
            return .infinity
        }
    }

    private func visibleSectionWindow(for target: RefreshTarget) -> TimeInterval {
        switch target {
        case .sectionList:
            return 60
        case .visibleDetail:
            return 120
        case .chatList, .taskCounts, .pinnedMetadata, .archiveList:
            return .infinity
        }
    }

    private func dedupedTargets(_ targets: [RefreshTarget]) -> [RefreshTarget] {
        var seen = Set<RefreshTarget>()
        return targets.filter { seen.insert($0).inserted }
    }
}
