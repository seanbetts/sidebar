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
}
