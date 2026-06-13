import XCTest
@testable import sideBar

final class TranscriptPrimitivesTests: XCTestCase {
    func testTranscriptSegmentRevisionKeepsStableIdentity() {
        let id = UUID()
        let original = TranscriptSegment(
            id: id,
            revision: 0,
            text: "We ship on Friday",
            startTime: 1,
            endTime: 4,
            isFinal: false,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let revised = original.revised(
            text: "We ship the beta on Friday",
            isFinal: true,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(revised.id, id)
        XCTAssertEqual(revised.revision, 1)
        XCTAssertEqual(revised.text, "We ship the beta on Friday")
        XCTAssertTrue(revised.isFinal)
    }

    func testFakeTranscriptionSessionYieldsConfiguredEvents() async {
        let segment = TranscriptSegment(
            text: "Decision is confirmed",
            startTime: 0,
            endTime: 3,
            isFinal: true
        )
        let session = FakeTranscriptionSession(events: [
            .segmentFinalized(segment),
            .completed
        ])

        var received: [TranscriptionEvent] = []
        for await event in session.events {
            received.append(event)
        }

        XCTAssertEqual(received, [.segmentFinalized(segment), .completed])
    }
}
