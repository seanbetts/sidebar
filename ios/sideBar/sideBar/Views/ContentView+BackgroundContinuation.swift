import SwiftUI

extension ContentView {
    struct SignedInBackgroundContinuationPlan: Equatable {
        let shouldScheduleWidgetRefresh: Bool
        let shouldScheduleWriteQueueFlush: Bool
        let shouldNotifyWebsiteQueueCoordinator: Bool
    }

    static func signedInBackgroundContinuationPlan(
        isAuthenticated: Bool,
        pendingWriteCount: Int
    ) -> SignedInBackgroundContinuationPlan {
        guard isAuthenticated else {
            return SignedInBackgroundContinuationPlan(
                shouldScheduleWidgetRefresh: false,
                shouldScheduleWriteQueueFlush: false,
                shouldNotifyWebsiteQueueCoordinator: false
            )
        }

        return SignedInBackgroundContinuationPlan(
            shouldScheduleWidgetRefresh: true,
            shouldScheduleWriteQueueFlush: pendingWriteCount > 0,
            shouldNotifyWebsiteQueueCoordinator: true
        )
    }
}
