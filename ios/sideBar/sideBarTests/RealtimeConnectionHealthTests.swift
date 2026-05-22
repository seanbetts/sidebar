import XCTest
import Realtime
import Supabase
import sideBarShared
@testable import sideBar

@MainActor
final class RealtimeConnectionHealthTests: XCTestCase {
    private static var retainedAdapters: [SupabaseRealtimeAdapter] = []

    func testRealtimeHealthDoesNotCountChannelsFromPreviousSessionDuringTokenChange() {
        let adapter = retain(SupabaseRealtimeAdapter(config: .fallbackForTesting()))
        adapter.currentUserId = "user-1"
        adapter.currentAccessToken = "old-token"
        for domain in RealtimeSubscriptionDomain.allCases {
            adapter.setChannel(adapter.client.realtimeV2.channel("public:\(domain.table)-old"), for: domain)
        }
        adapter.updateRealtimeConnectionState()
        XCTAssertTrue(adapter.isRealtimeConnected)

        adapter.currentAccessToken = "new-token"
        adapter.setRealtimeConnected(false)
        adapter.setChannel(adapter.client.realtimeV2.channel("public:notes-new"), for: .notes)
        adapter.updateRealtimeConnectionState()

        XCTAssertFalse(adapter.isRealtimeConnected)
    }

    func testRealtimeHealthClearDecisionMatchesPlannedResubscribeWork() {
        let currentSession = RealtimeSubscriptionSession(userId: "user-1", accessToken: "token")
        let sameSession = RealtimeSubscriptionSession(userId: "user-1", accessToken: "token")!
        let reusePlan = SupabaseRealtimeAdapter.makeSubscriptionPlan(
            currentSession: currentSession,
            nextSession: sameSession
        ) { _ in true }

        XCTAssertFalse(SupabaseRealtimeAdapter.shouldClearRealtimeHealthBeforeAuthUpdate(plan: reusePlan))

        let tokenChangedPlan = SupabaseRealtimeAdapter.makeSubscriptionPlan(
            currentSession: currentSession,
            nextSession: RealtimeSubscriptionSession(userId: "user-1", accessToken: "new-token")!
        ) { _ in true }

        XCTAssertTrue(SupabaseRealtimeAdapter.shouldClearRealtimeHealthBeforeAuthUpdate(plan: tokenChangedPlan))
    }

    private func retain(_ adapter: SupabaseRealtimeAdapter) -> SupabaseRealtimeAdapter {
        Self.retainedAdapters.append(adapter)
        return adapter
    }
}
