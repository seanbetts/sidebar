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

    func testIngestParsesEntityChangedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: entity_changed\n" +
            "data: {\"entity_type\":\"website\",\"entity_id\":\"site-1\",\"change\":\"renamed\",\"patch\":{\"title\":\"Renamed\"},\n" +
            "data: \"invalidate\":[\"websites\",\"website:site-1\"]}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .entityChanged)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["entity_type"] as? String, "website")
        XCTAssertEqual(payload?["entity_id"] as? String, "site-1")
        XCTAssertEqual(payload?["change"] as? String, "renamed")
        let patch = payload?["patch"] as? [String: Any]
        XCTAssertEqual(patch?["title"] as? String, "Renamed")
        XCTAssertEqual(payload?["invalidate"] as? [String], ["websites", "website:site-1"])
    }

    func testIngestParsesEntityDeletedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: entity_deleted\n" +
            "data: {\"entity_type\":\"website\",\"entity_id\":\"site-1\",\"invalidate\":[\"websites\",\"website:site-1\"]}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .entityDeleted)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["entity_type"] as? String, "website")
        XCTAssertEqual(payload?["entity_id"] as? String, "site-1")
        XCTAssertEqual(payload?["invalidate"] as? [String], ["websites", "website:site-1"])
    }

    func testIngestParsesCollectionInvalidatedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: collection_invalidated\n" +
            "data: {\"targets\":[\"profile\",\"assistant_settings\"],\"tool_call_id\":\"tool-1\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .collectionInvalidated)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["targets"] as? [String], ["profile", "assistant_settings"])
        XCTAssertEqual(payload?["tool_call_id"] as? String, "tool-1")
    }

    func testIngestParsesToolStatusEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: tool_status\n" +
            "data: {\"name\":\"Rename Website\",\"status\":\"running\",\"tool_call_id\":\"tool-1\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .toolStatus)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["name"] as? String, "Rename Website")
        XCTAssertEqual(payload?["status"] as? String, "running")
        XCTAssertEqual(payload?["tool_call_id"] as? String, "tool-1")
    }

    func testIngestParsesWorkspacePatchEvent() {
        var parser = ChatStreamParser()
        let chunk = """
        event: workspace_patch
        data: {"version":1,"operations":[{"op":"swap_panes"}],"future_field":{"trace_id":"abc"}}


        """

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .workspacePatch)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["version"] as? Int, 1)
        let operations = payload?["operations"] as? [[String: Any]]
        XCTAssertEqual(operations?.first?["op"] as? String, "swap_panes")
        XCTAssertNotNil(payload?["future_field"] as? [String: Any])
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

    func testIngestBuffersSplitUTF8AcrossChunks() {
        var parser = ChatStreamParser()
        let chunk = "event: token\ndata: {\"content\":\"🙂\"}\n\n"
        let fullData = Data(chunk.utf8)
        let emojiRange = fullData.range(of: Data("🙂".utf8))
        XCTAssertNotNil(emojiRange)
        let splitIndex = (emojiRange?.lowerBound ?? 0) + 2
        let part1 = fullData.prefix(splitIndex)
        let part2 = fullData.suffix(from: splitIndex)

        let first = parser.ingest(Data(part1))
        XCTAssertTrue(first.isEmpty)

        let second = parser.ingest(Data(part2))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.type, .token)
        let payload = second.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["content"] as? String, "🙂")
    }

    func testIngestIgnoresUnknownEventType() {
        var parser = ChatStreamParser()
        let chunk = "event: unknown\ndata: {\"text\":\"hi\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertTrue(events.isEmpty)
    }

    func testIngestCapsOversizedPartialEventBuffer() {
        var parser = ChatStreamParser(maxBufferSize: 65_536)
        let oversizedChunk = String(repeating: "a", count: 1_200_000)

        let events = parser.ingest(Data(oversizedChunk.utf8))

        XCTAssertTrue(events.isEmpty)
        let mirroredBuffer = Mirror(reflecting: parser).children
            .first(where: { $0.label == "buffer" })?.value as? Data
        XCTAssertEqual(mirroredBuffer?.count, 65_536)
    }
}
