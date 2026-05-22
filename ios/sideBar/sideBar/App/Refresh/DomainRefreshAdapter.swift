import Foundation

@MainActor
protocol DomainRefreshAdapter: AnyObject {
    var section: AppSection { get }
    var hasVisibleDetail: Bool { get }
    var hasPinnedMetadata: Bool { get }
    func prepareForPresentation(canAttemptServerRead: Bool) async
    func refresh(plan: RefreshPlan) async
    func applyMetadataPatch(for change: DomainSyncChange) async -> Bool
    func clearTransientState(after change: DomainSyncChange) async
}

extension DomainRefreshAdapter {
    var hasVisibleDetail: Bool { false }
    var hasPinnedMetadata: Bool { false }

    func prepareForPresentation(canAttemptServerRead: Bool) async {}
    func applyMetadataPatch(for change: DomainSyncChange) async -> Bool {
        _ = change
        return false
    }
    func clearTransientState(after change: DomainSyncChange) async {
        _ = change
    }
}

@MainActor
class SectionRefreshAdapter: DomainRefreshAdapter {
    let section: AppSection

    private let hasVisibleDetailHandler: @MainActor () -> Bool
    private let hasPinnedMetadataHandler: @MainActor () -> Bool
    private let prepareForPresentationHandler: @MainActor (Bool) async -> Void
    private let refreshesListHandler: @MainActor (RefreshPlan, AppSection) -> Bool
    private let refreshListHandler: @MainActor () async -> Void
    private let refreshVisibleDetailHandler: @MainActor () async -> Void
    private let applyMetadataPatchHandler: @MainActor (DomainSyncChange) async -> Bool
    private let clearTransientStateHandler: @MainActor (DomainSyncChange) async -> Void

    var hasVisibleDetail: Bool {
        hasVisibleDetailHandler()
    }

    var hasPinnedMetadata: Bool {
        hasPinnedMetadataHandler()
    }

    init(
        section: AppSection,
        hasVisibleDetail: @escaping @MainActor () -> Bool = { false },
        hasPinnedMetadata: @escaping @MainActor () -> Bool = { false },
        prepareForPresentation: @escaping @MainActor (Bool) async -> Void = { _ in },
        refreshesListWhen: @escaping @MainActor (RefreshPlan, AppSection) -> Bool = { plan, section in
            plan.containsListOrPinnedMetadata(for: section)
        },
        refreshList: @escaping @MainActor () async -> Void,
        refreshVisibleDetail: @escaping @MainActor () async -> Void = {},
        applyMetadataPatch: @escaping @MainActor (DomainSyncChange) async -> Bool = { _ in false },
        clearTransientState: @escaping @MainActor (DomainSyncChange) async -> Void = { _ in }
    ) {
        self.section = section
        self.hasVisibleDetailHandler = hasVisibleDetail
        self.hasPinnedMetadataHandler = hasPinnedMetadata
        self.prepareForPresentationHandler = prepareForPresentation
        self.refreshesListHandler = refreshesListWhen
        self.refreshListHandler = refreshList
        self.refreshVisibleDetailHandler = refreshVisibleDetail
        self.applyMetadataPatchHandler = applyMetadataPatch
        self.clearTransientStateHandler = clearTransientState
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        await prepareForPresentationHandler(canAttemptServerRead)
    }

    func applyMetadataPatch(for change: DomainSyncChange) async -> Bool {
        await applyMetadataPatchHandler(change)
    }

    func clearTransientState(after change: DomainSyncChange) async {
        await clearTransientStateHandler(change)
    }

    static func protectedListPreparation(
        clearError: @escaping @MainActor () -> Void = {},
        hydrateFromCache: @escaping @MainActor () async -> Void,
        loadWhenServerReadUnavailable: @escaping @MainActor () async -> Void
    ) -> @MainActor (Bool) async -> Void {
        { canAttemptServerRead in
            clearError()
            if canAttemptServerRead {
                await hydrateFromCache()
            } else {
                await loadWhenServerReadUnavailable()
            }
        }
    }

    func refresh(plan: RefreshPlan) async {
        guard plan.containsRefreshWork(for: section) else {
            return
        }

        if refreshesListHandler(plan, section) {
            await refreshListHandler()
        }

        if plan.containsVisibleDetail(for: section) {
            await refreshVisibleDetailHandler()
        }
    }
}
