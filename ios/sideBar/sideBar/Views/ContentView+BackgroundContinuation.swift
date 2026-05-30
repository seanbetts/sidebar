import SwiftUI

extension ContentView {
    struct SignedInBackgroundContinuationPlan: Equatable {
        let shouldScheduleTokenRefresh: Bool
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
                shouldScheduleTokenRefresh: false,
                shouldScheduleWidgetRefresh: false,
                shouldScheduleWriteQueueFlush: false,
                shouldNotifyWebsiteQueueCoordinator: false
            )
        }

        return SignedInBackgroundContinuationPlan(
            shouldScheduleTokenRefresh: true,
            shouldScheduleWidgetRefresh: true,
            shouldScheduleWriteQueueFlush: pendingWriteCount > 0,
            shouldNotifyWebsiteQueueCoordinator: true
        )
    }
}
