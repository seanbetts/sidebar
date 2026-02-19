import XCTest
@testable import sideBar

final class ContentViewLifecycleTests: XCTestCase {
    func testMakeMacInitialSelectionPlanDefaultsToChatWithoutPendingSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: nil)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertNil(plan.focusedSection)
        XCTAssertFalse(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanUsesPendingNonChatSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .websites)

        XCTAssertEqual(plan.primarySection, .websites)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertEqual(plan.lastNonChatSection, .websites)
        XCTAssertEqual(plan.sidebarSelection, .websites)
        XCTAssertEqual(plan.focusedSection, .websites)
        XCTAssertTrue(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanHandlesPendingChatSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .chat)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertEqual(plan.focusedSection, .chat)
        XCTAssertTrue(plan.shouldConsumeCommandSelection)
    }

    func testMakeMacInitialSelectionPlanIgnoresPendingSettingsSelection() {
        let plan = ContentView.makeMacInitialSelectionPlan(pendingSelection: .settings)

        XCTAssertNil(plan.primarySection)
        XCTAssertEqual(plan.secondarySection, .chat)
        XCTAssertNil(plan.lastNonChatSection)
        XCTAssertEqual(plan.sidebarSelection, .chat)
        XCTAssertNil(plan.focusedSection)
        XCTAssertFalse(plan.shouldConsumeCommandSelection)
    }

    func testMakeInitialPhoneChatActionCreatesConversationWhenNoneExist() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: nil,
            conversationIds: []
        )

        XCTAssertEqual(action, .createConversation)
    }

    func testMakeInitialPhoneChatActionSelectsFirstConversationWhenAvailable() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: nil,
            conversationIds: ["conversation-1", "conversation-2"]
        )

        XCTAssertEqual(action, .selectConversation("conversation-1"))
    }

    func testMakeInitialPhoneChatActionDoesNothingWhenAlreadySelected() {
        let action = ContentView.makeInitialPhoneChatAction(
            selectedConversationId: "conversation-9",
            conversationIds: ["conversation-1"]
        )

        XCTAssertEqual(action, .none)
    }
}
