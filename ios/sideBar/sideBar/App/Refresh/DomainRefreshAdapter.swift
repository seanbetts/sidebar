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
