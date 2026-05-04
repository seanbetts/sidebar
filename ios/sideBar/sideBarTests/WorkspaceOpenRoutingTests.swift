import XCTest
import sideBarShared
@testable import sideBar

final class WorkspaceOpenRoutingTests: XCTestCase {
    func testFileResolverMatchesStoredPathWhenRequestUsesPathAsID() {
        let item = makeFileItem(
            id: "file-123",
            filename: "brief.pdf",
            path: "Projects/Orion/brief.pdf"
        )

        let resolved = WorkspaceOpenFileResolver.resolveFileID(
            request: WorkspaceEntityOpenRequest(
                entity: WorkspaceEntityReference(
                    type: "file",
                    id: "Projects/Orion/brief.pdf",
                    title: "brief.pdf"
                ),
                routeURL: nil,
                section: .files
            ),
            items: [item]
        )

        XCTAssertEqual(resolved, "file-123")
    }

    func testFileResolverPrefersExplicitFileID() {
        let item = makeFileItem(
            id: "file-123",
            filename: "brief.pdf",
            path: "Projects/Orion/brief.pdf"
        )

        let resolved = WorkspaceOpenFileResolver.resolveFileID(
            request: WorkspaceEntityOpenRequest(
                entity: WorkspaceEntityReference(
                    type: "file",
                    id: "file-123",
                    title: "brief.pdf",
                    path: "Projects/Orion/brief.pdf"
                ),
                routeURL: nil,
                section: .files
            ),
            items: [item]
        )

        XCTAssertEqual(resolved, "file-123")
    }

    func testWorkspaceOpenFailureEncodesAssistantContextPayload() {
        let failure = WorkspaceOpenFailure(
            entityType: "file",
            entityID: "Projects/Orion/brief.pdf",
            title: "brief.pdf",
            message: "File not found."
        )

        let payload = failure.contextPayload

        XCTAssertEqual(payload["entity_type"]?.value as? String, "file")
        XCTAssertEqual(payload["entity_id"]?.value as? String, "Projects/Orion/brief.pdf")
        XCTAssertEqual(payload["title"]?.value as? String, "brief.pdf")
        XCTAssertEqual(payload["message"]?.value as? String, "File not found.")
    }

    private func makeFileItem(
        id: String,
        filename: String,
        path: String
    ) -> IngestionListItem {
        IngestionListItem(
            file: IngestedFileMeta(
                id: id,
                filenameOriginal: filename,
                path: path,
                mimeOriginal: "application/pdf",
                sizeBytes: 1024,
                sha256: nil,
                pinned: nil,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-05-04T12:00:00Z",
                updatedAt: "2026-05-04T12:00:00Z",
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "ready",
                stage: "ready",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: "2026-05-04T12:00:00Z"
            ),
            recommendedViewer: "pdf"
        )
    }
}
