import XCTest
import sideBarShared
@testable import sideBar

final class SearchTextMatcherTests: XCTestCase {
    func testContainsIsCaseAndDiacriticInsensitive() {
        let query = SearchTextMatcher.normalizedQuery("  CAFE  ")

        let matches = SearchTextMatcher.contains(
            normalizedQuery: query,
            in: ["Caf\u{00E9} notes"]
        )

        XCTAssertTrue(matches)
    }

    func testConversationSearchMatchesFirstMessageText() {
        let query = SearchTextMatcher.normalizedQuery("roadmap")
        let conversation = makeConversation(
            title: "Sprint Planning",
            firstMessage: "Roadmap review tomorrow"
        )

        let matches = ConversationsPanelView.conversationMatchesSearchQuery(
            query,
            conversation: conversation
        )

        XCTAssertTrue(matches)
    }

    func testConversationSearchReturnsFalseWhenNoFieldsMatch() {
        let query = SearchTextMatcher.normalizedQuery("invoice")
        let conversation = makeConversation(
            title: "Sprint Planning",
            firstMessage: "Roadmap review tomorrow"
        )

        let matches = ConversationsPanelView.conversationMatchesSearchQuery(
            query,
            conversation: conversation
        )

        XCTAssertFalse(matches)
    }

    func testConversationPanelLoadErrorShownWhenSearchEmptyAndNoConversations() {
        let message = ConversationsPanelView.loadErrorMessageForEmptyState(
            searchQuery: "",
            conversations: [],
            errorMessage: "Network connection failed. Please check your internet."
        )

        XCTAssertEqual(message, "Network connection failed. Please check your internet.")
    }

    func testConversationPanelLoadErrorHiddenWhileSearching() {
        let message = ConversationsPanelView.loadErrorMessageForEmptyState(
            searchQuery: "project",
            conversations: [],
            errorMessage: "Network connection failed. Please check your internet."
        )

        XCTAssertNil(message)
    }

    private func makeConversation(title: String, firstMessage: String?) -> Conversation {
        Conversation(
            id: "conv-1",
            title: title,
            titleGenerated: false,
            createdAt: "2026-02-19T12:00:00Z",
            updatedAt: "2026-02-19T12:00:00Z",
            messageCount: 1,
            firstMessage: firstMessage,
            isArchived: false
        )
    }
}
