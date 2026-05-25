import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamSyncPayloadFailureTests: ChatViewModelTestCase {
    func testMalformedPrimitiveSyncPayloadSchedulesDecodeFailureRefresh() async {
        let refreshCoordinator = DecodeFailureRefreshCoordinator()
        let refreshContext = RefreshContext(
            visibleSection: .chat,
            hasVisibleDetail: true,
            pinnedSections: [],
            lastOpenedSection: nil,
            staleTargets: [],
            canAttemptServerRead: true
        )
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let scheduled = expectation(description: "scheduled decode failure refresh")
        refreshCoordinator.onDecodeFailureRefresh = {
            scheduled.fulfill()
        }
        viewModel.selectedConversationId = "conv-1"
        viewModel.configureRefreshCoordinator(refreshCoordinator) {
            refreshContext
        }

        viewModel.handle(
            event: ChatStreamEvent(
                type: .entityChanged,
                data: AnyCodable([
                    "entity_type": "website",
                    "patch": ["title": "Renamed without an id"]
                ])
            )
        )

        await fulfillment(of: [scheduled], timeout: 1.0)
        XCTAssertEqual(refreshCoordinator.decodeFailureRefreshes.map(\.section), [.chat])
        XCTAssertEqual(refreshCoordinator.decodeFailureRefreshes.map(\.context), [refreshContext])
    }
}

@MainActor
private final class DecodeFailureRefreshCoordinator: RefreshCoordinatorType {
    private(set) var decodeFailureRefreshes: [(section: AppSection, context: RefreshContext)] = []
    var onDecodeFailureRefresh: (() -> Void)?

    func handleActivation(_ request: ActivationRefreshRequest) async {
        _ = request
    }

    func prepareVisibleSectionForPresentation(_ section: AppSection?, canAttemptServerRead: Bool) async {
        _ = section
        _ = canAttemptServerRead
    }

    func hasVisibleDetail(for section: AppSection?) -> Bool {
        section == .chat
    }

    func pinnedSections() -> [AppSection] {
        []
    }

    func refresh(trigger: RefreshTrigger, context: RefreshContext) async {
        _ = trigger
        _ = context
    }

    func scheduleRealtimeInvalidation(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func scheduleDecodeFailureRefresh(section: AppSection, context: RefreshContext) async {
        decodeFailureRefreshes.append((section, context))
        onDecodeFailureRefresh?()
    }

    func scheduleJobTerminalRefresh(_ change: DomainSyncChange, context: RefreshContext) async {
        _ = change
        _ = context
    }

    func visibleSectionDidChange(to section: AppSection?, context: RefreshContext) async {
        _ = section
        _ = context
    }
}
