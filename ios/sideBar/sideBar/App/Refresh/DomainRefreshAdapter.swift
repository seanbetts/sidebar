import Foundation

@MainActor
protocol DomainRefreshAdapter: AnyObject {
    var section: AppSection { get }
    var hasVisibleDetail: Bool { get }
    var hasPinnedMetadata: Bool { get }
    func prepareForPresentation(canAttemptServerRead: Bool) async
    func refresh(plan: RefreshPlan) async
}

extension DomainRefreshAdapter {
    var hasVisibleDetail: Bool { false }
    var hasPinnedMetadata: Bool { false }

    func prepareForPresentation(canAttemptServerRead: Bool) async {}
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
        refreshVisibleDetail: @escaping @MainActor () async -> Void = {}
    ) {
        self.section = section
        self.hasVisibleDetailHandler = hasVisibleDetail
        self.hasPinnedMetadataHandler = hasPinnedMetadata
        self.prepareForPresentationHandler = prepareForPresentation
        self.refreshesListHandler = refreshesListWhen
        self.refreshListHandler = refreshList
        self.refreshVisibleDetailHandler = refreshVisibleDetail
    }

    func prepareForPresentation(canAttemptServerRead: Bool) async {
        await prepareForPresentationHandler(canAttemptServerRead)
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
