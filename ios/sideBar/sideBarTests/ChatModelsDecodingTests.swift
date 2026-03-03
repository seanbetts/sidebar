import XCTest
@testable import sideBar

@MainActor
final class ChatModelsDecodingTests: XCTestCase {
    func testConversationDecodesWhenMessageStatusMissingOrNull() throws {
        let payload = """
        {
          "id": "conv-1",
          "title": "Chat",
          "titleGenerated": false,
          "createdAt": "2026-02-18T10:00:00Z",
          "updatedAt": "2026-02-18T10:05:00Z",
          "messageCount": 2,
          "firstMessage": "Hello",
          "messages": [
            {
              "id": "msg-1",
              "role": "user",
              "content": "Hello",
              "timestamp": "2026-02-18T10:00:00Z"
            },
            {
              "id": "msg-2",
              "role": "assistant",
              "content": "Hi there",
              "status": null,
              "timestamp": "2026-02-18T10:00:01Z"
            }
          ]
        }
        """

        let conversation = try JSONDecoder().decode(
            ConversationWithMessages.self,
            from: Data(payload.utf8)
        )

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages[0].status, .complete)
        XCTAssertEqual(conversation.messages[1].status, .complete)
    }

    func testConversationDecodesWhenToolCallsPayloadIsMalformed() throws {
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
              "content": "Done",
              "status": "complete",
              "toolCalls": "unexpected-shape",
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
        XCTAssertNil(conversation.messages[0].toolCalls)
        XCTAssertEqual(conversation.messages[0].status, .complete)
    }

    func testConversationDecodesToolCallSkillMetadataWithSnakeCaseKeys() throws {
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
              "content": "Done",
              "status": "complete",
              "toolCalls": [
                {
                  "id": "tool-1",
                  "name": "Create Note",
                  "parameters": {},
                  "status": "success",
                  "skill_id": "notes",
                  "icon_key": "notes"
                }
              ],
              "timestamp": "2026-02-18T10:00:01Z"
            }
          ]
        }
        """

        let conversation = try JSONDecoder().decode(
            ConversationWithMessages.self,
            from: Data(payload.utf8)
        )

        let toolCall = conversation.messages[0].toolCalls?.first
        XCTAssertEqual(toolCall?.skillId, "notes")
        XCTAssertEqual(toolCall?.iconKey, "notes")
    }
}
