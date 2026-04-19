import XCTest

final class ChatMessageRowAccessibilitySourceTests: XCTestCase {
    func testChatMessageRowExposesStableMessageContentIdentifier() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains("chat-message-content-\\(message.id)"),
            "ChatMessageRow should expose a stable accessibility identifier for message content."
        )
    }

    func testChatMessageRowExposesRawMessageContentAsAccessibilityLabel() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains(".accessibilityLabel(message.content)"),
            "ChatMessageRow should expose raw message content through accessibility for UI tests and assistive technology."
        )
    }

    func testChatMessageRowExposesStableRowIdentifier() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains("chat-message-row-\\(message.id)"),
            "ChatMessageRow should expose a stable accessibility identifier for the full message row."
        )
    }

    func testChatMessageRowExposesRawMessageContentAsAccessibilityValue() throws {
        let source = try normalizedChatMessageRowSource()

        XCTAssertTrue(
            source.contains(".accessibilityValue(message.content)"),
            "ChatMessageRow should expose raw message content as an accessibility value for UI-test lookup."
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
