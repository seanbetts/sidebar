import Foundation

@MainActor
protocol DomainRefreshAdapter: AnyObject {
    var section: AppSection { get }
    func refresh(plan: RefreshPlan) async
}
