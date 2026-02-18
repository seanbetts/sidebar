import XCTest
@testable import sideBar

final class GIFAnimationTimingTests: XCTestCase {
    func testNormalizedDurationKeepsTwentyMilliseconds() {
        XCTAssertEqual(
            GIFAnimationTiming.normalizedDuration(0.02),
            0.02,
            accuracy: 0.000_001
        )
    }

    func testNormalizedDurationClampsSubTwentyMilliseconds() {
        XCTAssertEqual(
            GIFAnimationTiming.normalizedDuration(0.01),
            GIFAnimationTiming.minimumFrameDuration,
            accuracy: 0.000_001
        )
    }

    func testRepeatCountUsesCentisecondResolution() {
        XCTAssertEqual(GIFAnimationTiming.repeatCount(for: 0.02), 2)
        XCTAssertEqual(GIFAnimationTiming.repeatCount(for: 0.03), 3)
    }

    func testExpandedDurationMatchesRepeatedFrameCount() {
        XCTAssertEqual(
            GIFAnimationTiming.expandedDuration(for: 395),
            3.95,
            accuracy: 0.000_001
        )
    }
}
