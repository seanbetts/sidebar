import XCTest
@testable import sideBar

final class IntelligenceDiagnosticsTests: XCTestCase {
    func testDiagnosticsEventContainsRouteMetadataButNotPromptText() {
        let recorder = CapturingIntelligenceDiagnosticsRecorder()
        let metadata = IntelligenceRouteMetadata(
            descriptor: .appleOnDevice(capability: .liveNotes),
            latencyMs: 42,
            structuredOutputValid: true,
            failureCategory: nil,
            contextBudget: .init(usedTokens: 99, contextSize: 4_096),
            extra: ["prompt": "secret", "chunk_id": "abc"]
        )

        recorder.record(.modelCompleted(metadata))

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events[0].metadata.extra, ["chunk_id": "abc"])
        XCTAssertFalse(recorder.events[0].debugDescription.contains("secret"))
        XCTAssertFalse(recorder.events[0].debugDescription.contains("abc"))
    }

    func testFailureEventMapsFailureCategory() {
        let recorder = CapturingIntelligenceDiagnosticsRecorder()
        recorder.record(.modelFailed(
            descriptor: .appleOnDevice(capability: .liveNotes),
            category: .structuredOutputInvalid,
            latencyMs: 12
        ))

        XCTAssertEqual(recorder.events[0].metadata.failureCategory, .structuredOutputInvalid)
    }
}
