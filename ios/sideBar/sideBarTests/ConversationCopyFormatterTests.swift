import XCTest
@testable import sideBar

final class ConversationCopyFormatterTests: XCTestCase {
    func testFormattedTranscriptIncludesUserAndAssistantMessages() {
        let messages = [
            Message(
                id: "m1",
                role: .user,
                content: "Hello",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-02-18T00:00:00Z",
                error: nil
            ),
            Message(
                id: "m2",
                role: .assistant,
                content: "Hi there",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-02-18T00:00:01Z",
                error: nil
            )
        ]

        let formatted = ConversationCopyFormatter.formattedTranscript(
            title: "Trip Planning",
            messages: messages,
            assistantName: "Avery"
        )

        XCTAssertTrue(formatted.contains("Chat: Trip Planning"))
        XCTAssertTrue(formatted.contains("You:\nHello"))
        XCTAssertTrue(formatted.contains("Avery:\nHi there"))
    }

    func testFormattedTranscriptFallsBackToErrorContentAndSkipsEmptyMessages() {
        let messages = [
            Message(
                id: "m1",
                role: .assistant,
                content: " ",
                status: .error,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-02-18T00:00:00Z",
                error: "Request failed"
            ),
            Message(
                id: "m2",
                role: .assistant,
                content: "",
                status: .complete,
                toolCalls: nil,
                needsNewline: nil,
                timestamp: "2026-02-18T00:00:01Z",
                error: nil
            )
        ]

        let formatted = ConversationCopyFormatter.formattedTranscript(
            title: " ",
            messages: messages,
            assistantName: "Agent"
        )

        XCTAssertTrue(formatted.contains("Chat: Chat"))
        XCTAssertTrue(formatted.contains("Agent:\nRequest failed"))
        XCTAssertFalse(formatted.contains("Agent:\n\n"))
    }

    func testExportFilenameSanitizesConversationTitle() {
        let filename = ConversationCopyFormatter.exportFilename(title: "Trip Planning / Q2?")

        XCTAssertEqual(filename, "Trip-Planning-Q2.txt")
    }

    func testExportFilenameFallsBackToDefaultTitleWhenEmpty() {
        let filename = ConversationCopyFormatter.exportFilename(title: "   ")

        XCTAssertEqual(filename, "Chat.txt")
    }
}
