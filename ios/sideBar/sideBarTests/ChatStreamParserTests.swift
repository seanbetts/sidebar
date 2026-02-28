import XCTest
import sideBarShared
@testable import sideBar

final class ChatStreamParserTests: XCTestCase {
    func testIngestParsesSingleEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: token\ndata: {\"text\":\"hi\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .token)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["text"] as? String, "hi")
    }

    func testIngestBuffersPartialEvent() {
        var parser = ChatStreamParser()
        let part1 = "event: token\ndata: {\"text\":\"hi\""
        let part2 = "}\n\n"

        let first = parser.ingest(Data(part1.utf8))
        XCTAssertTrue(first.isEmpty)

        let second = parser.ingest(Data(part2.utf8))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.type, .token)
    }

    func testIngestIgnoresUnknownEventType() {
        var parser = ChatStreamParser()
        let chunk = "event: unknown\ndata: {\"text\":\"hi\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertTrue(events.isEmpty)
    }

    func testIngestParsesAssistantIdentityUpdatedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: assistant_identity_updated\ndata: {\"assistant_identity\":{\"name\":\"Navigator\"}}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .assistantIdentityUpdated)
        let payload = events.first?.data?.value as? [String: Any]
        let identity = payload?["assistant_identity"] as? [String: Any]
        XCTAssertEqual(identity?["name"] as? String, "Navigator")
    }

    func testIngestParsesOtherPreferencesUpdatedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: other_preferences_updated\ndata: {\"weather_unit\":\"fahrenheit\",\"biometric_unlock_enabled\":true}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .otherPreferencesUpdated)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["weather_unit"] as? String, "fahrenheit")
        XCTAssertEqual(payload?["biometric_unlock_enabled"] as? Bool, true)
    }

    func testIngestParsesWorkspacePatchEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: workspace_patch\ndata: {\"version\":1,\"operations\":[{\"op\":\"swap_panes\"}],\"future_field\":{\"trace_id\":\"abc\"}}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .workspacePatch)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["version"] as? Int, 1)
        let operations = payload?["operations"] as? [[String: Any]]
        XCTAssertEqual(operations?.first?["op"] as? String, "swap_panes")
        XCTAssertNotNil(payload?["future_field"] as? [String: Any])
    }
}
