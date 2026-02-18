import XCTest
import sideBarShared
@testable import sideBar

final class FilesWorkspaceDisplayPolicyTests: XCTestCase {
    func testMainWorkspaceUploadProgressIsDisabledForUploadingItems() {
        let item = makeItem(status: "uploading", stage: "uploading", progress: 0.42)

        XCTAssertFalse(FilesWorkspaceDisplayPolicy.shouldShowUploadProgressInMainWorkspace(for: item))
    }

    func testMainWorkspaceUploadProgressIsDisabledForProcessingItems() {
        let item = makeItem(status: "processing", stage: "extracting", progress: 0.9)

        XCTAssertFalse(FilesWorkspaceDisplayPolicy.shouldShowUploadProgressInMainWorkspace(for: item))
    }

    private func makeItem(status: String, stage: String, progress: Double?) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "file.txt",
                path: "/file.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 10,
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
                status: status,
                stage: stage,
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: progress,
                attempts: 0,
                updatedAt: nil
            ),
            recommendedViewer: nil
        )
    }
}
