import XCTest

final class ChatMessageRowAccessibilitySourceTests: XCTestCase {
    func testChatMessageRowExposesStableMessageContentIdentifier() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains("chat-message-content-\\(message.id)"),
            "ChatMessageRow should expose a stable accessibility identifier for message content."
        )
    }

    func testChatMessageRowExposesRenderedMessageContentAsAccessibilityLabel() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains(".accessibilityLabel(renderedMessageContent)"),
            "ChatMessageRow should expose rendered message content through accessibility for UI tests and assistive technology."
        )
    }

    func testChatMessageRowExposesStableRowIdentifier() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains("chat-message-row-\\(message.id)"),
            "ChatMessageRow should expose a stable accessibility identifier for the full message row."
        )
    }

    func testChatMessageRowExposesRenderedMessageContentAsAccessibilityValue() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains(".accessibilityValue(renderedMessageContent)"),
            "ChatMessageRow should expose rendered message content as an accessibility value for UI-test lookup."
        )
    }

    func testChatMessageRowRendersToolActionsAfterMessageContent() throws {
        let source = try normalizedChatMessageRowSource()
        let contentIndex = try XCTUnwrap(source.range(of: "SideBarMarkdown(text:renderedMessageContent,style:.chat)")?.lowerBound)
        let actionsIndex = try XCTUnwrap(source.range(of: "ChatToolActionListView(")?.lowerBound)

        XCTAssertLessThan(
            contentIndex,
            actionsIndex,
            "Inline tool actions should appear after the assistant message content."
        )
    }

    func testChatMessageRowFallsBackToConfirmationPromptForEmptyAssistantMessage() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains("guardmessage.role==.assistant,messageContentIsEffectivelyEmptyelse")
        )
        XCTAssertTrue(
            source.contains("toolActions.first{$0.kind==.confirmation}?.confirmationPrompt")
        )
    }

    private func normalizedChatMessageRowSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sideBar/Views/Chat/ChatMessageRow.swift")
        do {
            return try String(contentsOf: url, encoding: .utf8)
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\n", with: "")
        } catch {
            XCTFail("Failed to read ChatMessageRow source: \(error)", file: file, line: line)
            throw error
        }
    }
}
