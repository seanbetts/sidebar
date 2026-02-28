import XCTest
@testable import sideBar

final class IngestionDetailViewTests: XCTestCase {
    func testShouldShowProcessingStateFalseWhenErrorMessageIsPresent() {
        XCTAssertFalse(
            IngestionDetailView.shouldShowProcessingState(
                status: "processing",
                errorMessage: "Could not refresh file status. Re-open the file to retry."
            )
        )
    }

    func testShouldShowProcessingStateTrueWhenStatusIsNonTerminalAndNoError() {
        XCTAssertTrue(
            IngestionDetailView.shouldShowProcessingState(
                status: "processing",
                errorMessage: nil
            )
        )
    }

    func testShouldShowProcessingStateFalseForTerminalStatus() {
        XCTAssertFalse(
            IngestionDetailView.shouldShowProcessingState(
                status: "ready",
                errorMessage: nil
            )
        )
    }

    func testShouldShowProcessingStateFalseWhenViewerStateIsAvailable() {
        XCTAssertFalse(
            IngestionDetailView.shouldShowProcessingState(
                status: "processing",
                errorMessage: nil,
                hasViewerState: true
            )
        )
    }

    func testIsFailedStateTrueForFailedStatusWithoutViewer() {
        XCTAssertTrue(
            IngestionDetailView.isFailedState(
                status: "failed",
                hasViewerState: false
            )
        )
    }

    func testIsFailedStateFalseWhenViewerStateIsAvailable() {
        XCTAssertFalse(
            IngestionDetailView.isFailedState(
                status: "failed",
                hasViewerState: true
            )
        )
    }
}
