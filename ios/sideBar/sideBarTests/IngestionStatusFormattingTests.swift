import XCTest
@testable import sideBar

final class IngestionStatusFormattingTests: XCTestCase {
    func testIngestionStatusLabelUsesKnownQueuedStatus() {
        let job = makeJob(status: "queued", stage: nil, userMessage: nil, errorMessage: nil)

        XCTAssertEqual(ingestionStatusLabel(for: job), "Queued")
    }

    func testIngestionStatusDetailOmitsDuplicateQueuedMessage() {
        let job = makeJob(status: "queued", stage: "queued", userMessage: "Queued", errorMessage: nil)

        XCTAssertNil(ingestionStatusDetail(for: job, statusLabel: "Queued"))
    }

    func testIngestionStatusDetailPrefersNonDuplicateUserMessage() {
        let job = makeJob(
            status: "processing",
            stage: "extracting",
            userMessage: "Preparing file content",
            errorMessage: nil
        )

        XCTAssertEqual(
            ingestionStatusDetail(for: job, statusLabel: "Preparing"),
            "Preparing file content"
        )
    }

    func testIngestionStatusDetailFallsBackToErrorMessage() {
        let job = makeJob(status: "failed", stage: nil, userMessage: nil, errorMessage: "File too large")

        XCTAssertEqual(
            ingestionStatusDetail(for: job, statusLabel: "Needs attention"),
            "File too large"
        )
    }

    private func makeJob(
        status: String?,
        stage: String?,
        userMessage: String?,
        errorMessage: String?
    ) -> IngestionJob {
        IngestionJob(
            status: status,
            stage: stage,
            errorCode: nil,
            errorMessage: errorMessage,
            userMessage: userMessage,
            progress: nil,
            attempts: 0,
            updatedAt: nil
        )
    }
}
