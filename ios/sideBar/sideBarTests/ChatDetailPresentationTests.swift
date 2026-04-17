import XCTest
import sideBarShared
@testable import sideBar

final class ChatDetailPresentationTests: XCTestCase {
    func testMissingConversationContentPlaceholderShowsForExistingConversationWithoutMessages() {
        let conversation = Conversation(
            id: "conv-1",
            title: "Existing chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            messageCount: 3,
            firstMessage: "Hello",
            isArchived: false
        )

        XCTAssertTrue(
            ChatDetailPresentation.shouldShowMissingConversationPlaceholder(
                selectedConversationId: "conv-1",
                selectedConversation: conversation,
                messages: [],
                isLoadingMessages: false,
                errorMessage: nil
            )
        )
    }

    func testMissingConversationContentPlaceholderDoesNotShowForNewBlankConversation() {
        let conversation = Conversation(
            id: "conv-1",
            title: "New chat",
            titleGenerated: false,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            messageCount: 0,
            firstMessage: nil,
            isArchived: false
        )

        XCTAssertFalse(
            ChatDetailPresentation.shouldShowMissingConversationPlaceholder(
                selectedConversationId: "conv-1",
                selectedConversation: conversation,
                messages: [],
                isLoadingMessages: false,
                errorMessage: nil
            )
        )
    }

    func testMissingConversationContentPlaceholderDoesNotShowWhileMessagesAreLoading() {
        XCTAssertFalse(
            ChatDetailPresentation.shouldShowMissingConversationPlaceholder(
                selectedConversationId: "conv-1",
                selectedConversation: nil,
                messages: [],
                isLoadingMessages: true,
                errorMessage: nil
            )
        )
    }

    func testMissingConversationContentPlaceholderShowsWhenSelectionMetadataIsMissing() {
        XCTAssertTrue(
            ChatDetailPresentation.shouldShowMissingConversationPlaceholder(
                selectedConversationId: "conv-1",
                selectedConversation: nil,
                messages: [],
                isLoadingMessages: false,
                errorMessage: nil
            )
        )
    }
}
