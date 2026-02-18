import XCTest
@testable import ShareExtension

final class ShareGIFAnimationTimingTests: XCTestCase {
    func testNormalizedDurationKeepsTwentyMilliseconds() {
        XCTAssertEqual(
            ShareGIFAnimationTiming.normalizedDuration(0.02),
            0.02,
            accuracy: 0.000_001
        )
    }

    func testNormalizedDurationClampsSubTwentyMilliseconds() {
        XCTAssertEqual(
            ShareGIFAnimationTiming.normalizedDuration(0.01),
            ShareGIFAnimationTiming.minimumFrameDuration,
            accuracy: 0.000_001
        )
    }

    func testRepeatCountUsesCentisecondResolution() {
        XCTAssertEqual(ShareGIFAnimationTiming.repeatCount(for: 0.02), 2)
        XCTAssertEqual(ShareGIFAnimationTiming.repeatCount(for: 0.03), 3)
    }

    func testExpandedDurationMatchesRepeatedFrameCount() {
        XCTAssertEqual(
            ShareGIFAnimationTiming.expandedDuration(for: 395),
            3.95,
            accuracy: 0.000_001
        )
    }
}
