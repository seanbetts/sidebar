import XCTest
@testable import sideBar

@MainActor
final class ChatStructuredContentDecodingTests: XCTestCase {
    func testConversationDecodesStructuredMessageContentArrays() throws {
        let payload = """
        {
          "id": "conv-1",
          "title": "Chat",
          "titleGenerated": false,
          "createdAt": "2026-02-18T10:00:00Z",
          "updatedAt": "2026-02-18T10:05:00Z",
          "messageCount": 1,
          "firstMessage": "Hello",
          "messages": [
            {
              "id": "msg-1",
              "role": "assistant",
              "content": [
                {
                  "type": "output_text",
                  "text": "First paragraph."
                },
                {
                  "type": "output_text",
                  "text": "Second paragraph."
                }
              ],
              "status": "complete",
              "timestamp": "2026-02-18T10:00:01Z"
            }
          ]
        }
        """

        let conversation = try JSONDecoder().decode(
            ConversationWithMessages.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(
            conversation.messages[0].content,
            "First paragraph.\n\nSecond paragraph."
        )
    }

    func testConversationDecodesStructuredMessageContentObjects() throws {
        let payload = """
        {
          "id": "conv-1",
          "title": "Chat",
          "titleGenerated": false,
          "createdAt": "2026-02-18T10:00:00Z",
          "updatedAt": "2026-02-18T10:05:00Z",
          "messageCount": 1,
          "firstMessage": "Hello",
          "messages": [
            {
              "id": "msg-1",
              "role": "assistant",
              "content": {
                "content": [
                  {
                    "type": "output_text",
                    "text": "Recovered text"
                  }
                ]
              },
              "status": "complete",
              "timestamp": "2026-02-18T10:00:01Z"
            }
          ]
        }
        """

        let conversation = try JSONDecoder().decode(
            ConversationWithMessages.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(conversation.messages.count, 1)
        XCTAssertEqual(conversation.messages[0].content, "Recovered text")
    }
}
