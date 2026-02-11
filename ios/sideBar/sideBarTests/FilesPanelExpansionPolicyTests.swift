import XCTest
import sideBarShared
@testable import sideBar

final class FilesPanelExpansionPolicyTests: XCTestCase {
    func testShouldInitializeBaselineWhenStable() {
        XCTAssertTrue(
            FilesPanelExpansionPolicy.shouldInitializeBaseline(
                isLoading: false,
                awaitingInitialLoad: false,
                hasBaseline: false
            )
        )
    }

    func testShouldNotInitializeBaselineDuringInitialLoad() {
        XCTAssertFalse(
            FilesPanelExpansionPolicy.shouldInitializeBaseline(
                isLoading: false,
                awaitingInitialLoad: true,
                hasBaseline: false
            )
        )
    }

    func testShouldNotAutoExpandVideoWithoutBaseline() {
        let items = [makeItem(id: "yt-1", mimeOriginal: "video/youtube")]

        XCTAssertFalse(
            FilesPanelExpansionPolicy.shouldAutoExpandVideo(
                hasBaseline: false,
                previousKnownFileIds: [],
                items: items
            )
        )
    }

    func testShouldAutoExpandVideoForNewYouTubeItemAfterBaseline() {
        let items = [
            makeItem(id: "existing", mimeOriginal: "application/pdf"),
            makeItem(id: "yt-2", mimeOriginal: "video/youtube")
        ]

        XCTAssertTrue(
            FilesPanelExpansionPolicy.shouldAutoExpandVideo(
                hasBaseline: true,
                previousKnownFileIds: ["existing"],
                items: items
            )
        )
    }

    func testShouldNotAutoExpandVideoWhenNoNewYouTubeItems() {
        let items = [
            makeItem(id: "yt-3", mimeOriginal: "video/youtube"),
            makeItem(id: "doc-1", mimeOriginal: "application/pdf")
        ]

        XCTAssertFalse(
            FilesPanelExpansionPolicy.shouldAutoExpandVideo(
                hasBaseline: true,
                previousKnownFileIds: ["yt-3"],
                items: items
            )
        )
    }

    private func makeItem(id: String, mimeOriginal: String) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: "\(id).txt",
                path: nil,
                mimeOriginal: mimeOriginal,
                sizeBytes: 1,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: nil,
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "ready",
                stage: "done",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 1,
                updatedAt: nil
            ),
            recommendedViewer: "text_original"
        )
    }
}
