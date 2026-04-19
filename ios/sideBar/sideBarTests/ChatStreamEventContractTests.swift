import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamEventContractTests: ChatViewModelTestCase {
    func testSyncProtocolParsesEveryDeclaredPrimitiveEvent() {
        let expectedEventNames: Set<String> = [
            "collection_invalidated",
            "entity_changed",
            "entity_deleted",
            "prompt_preview",
            "tool_status",
            "workspace_patch"
        ]
        XCTAssertEqual(Set(chatStreamCustomEventNames), expectedEventNames)

        var parser = ChatStreamParser()
        for eventName in chatStreamCustomEventNames {
            let chunk = "event: \(eventName)\ndata: {}\n\n"
            let events = parser.ingest(Data(chunk.utf8))
            XCTAssertEqual(
                events.map(\.type.rawValue),
                [eventName],
                "Expected parser coverage for primitive SSE event \(eventName)"
            )
        }
    }

    func testSyncProtocolDeclaresGeneratedEntityAndChangeConstants() {
        XCTAssertEqual(
            Set(chatStreamEntityTypeNames),
            [
                "assistant_settings",
                "conversation",
                "ingestion",
                "memory",
                "note",
                "onboarding_state",
                "preferences",
                "profile",
                "scratchpad",
                "website",
                "workspace"
            ]
        )

        XCTAssertEqual(
            Set(chatStreamChangeTypeNames),
            [
                "archived",
                "cleared",
                "completed",
                "created",
                "deleted",
                "moved",
                "pinned",
                "renamed",
                "unarchived",
                "unpinned",
                "updated"
            ]
        )

        XCTAssertEqual(
            Set(chatStreamEntitySyncPolicies.keys.map(\.rawValue)),
            Set(chatStreamEntityTypeNames),
            "Expected a client sync policy entry for every declared entity type"
        )
    }

    func testSyncProtocolBuildsHandlerForEveryDeclaredPrimitiveEvent() {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let expectedHandlerEvents: Set<String> = [
            "collection_invalidated",
            "complete",
            "entity_changed",
            "entity_deleted",
            "error",
            "prompt_preview",
            "token",
            "tool_call",
            "tool_result",
            "tool_status",
            "workspace_patch"
        ]
        let handlerEvents = Set(viewModel.streamEventHandlers.keys.map(\.rawValue))

        XCTAssertEqual(handlerEvents, expectedHandlerEvents)
        XCTAssertFalse(handlerEvents.contains("conversation_title_updated"))
        XCTAssertFalse(handlerEvents.contains("website_renamed"))
        XCTAssertFalse(handlerEvents.contains("profile_user_settings_updated"))
    }
}
