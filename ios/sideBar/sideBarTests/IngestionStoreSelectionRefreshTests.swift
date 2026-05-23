import Foundation
import XCTest
@testable import sideBar

@MainActor
final class IngestionStoreSelectionRefreshTests: XCTestCase {
    func testApplyListUpdateSyncsActiveMetaMetadataWithoutDroppingDerivatives() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )
        let initialMeta = IngestionMetaResponse(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "Original.txt",
                path: "/Original.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: "2026-01-10T00:00:00Z",
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "extracting",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: "2026-01-10T00:00:00Z"
            ),
            derivatives: [
                IngestionDerivative(
                    id: "file-1-d1",
                    kind: "text_original",
                    storageKey: "derivatives/file-1/text_original",
                    mime: "text/plain",
                    sizeBytes: 12
                )
            ],
            recommendedViewer: "text_original"
        )
        store.activeMeta = initialMeta

        store.applyListUpdate([
            IngestionStoreTestsSupport.makeItem(
                id: "file-1",
                filename: "Renamed.pdf",
                path: "/Renamed.pdf",
                mimeOriginal: "application/pdf",
                pinned: true,
                pinnedOrder: 0,
                status: "ready",
                stage: "ready",
                recommendedViewer: "viewer_pdf"
            )
        ], persist: true)

        XCTAssertEqual(store.activeMeta?.file.filenameOriginal, "Renamed.pdf")
        XCTAssertEqual(store.activeMeta?.file.path, "/Renamed.pdf")
        XCTAssertEqual(store.activeMeta?.file.mimeOriginal, "application/pdf")
        XCTAssertEqual(store.activeMeta?.file.pinned, true)
        XCTAssertEqual(store.activeMeta?.file.pinnedOrder, 0)
        XCTAssertEqual(store.activeMeta?.job.status, "ready")
        XCTAssertEqual(store.activeMeta?.job.stage, "ready")
        XCTAssertEqual(store.activeMeta?.recommendedViewer, "viewer_pdf")
        XCTAssertEqual(store.activeMeta?.derivatives.map(\.id), ["file-1-d1"])

        let cached: IngestionMetaResponse? = cache.get(key: CacheKeys.ingestionMeta(fileId: "file-1"))
        XCTAssertEqual(cached?.file.filenameOriginal, "Renamed.pdf")
        XCTAssertEqual(cached?.job.status, "ready")
        XCTAssertEqual(cached?.derivatives.map(\.id), ["file-1-d1"])
    }

    func testFileJobRealtimePatchesActiveMetaWithoutDroppingDerivatives() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )
        let initialMeta = IngestionMetaResponse(
            file: IngestedFileMeta(
                id: "file-1",
                filenameOriginal: "Original.txt",
                path: "/Original.txt",
                mimeOriginal: "text/plain",
                sizeBytes: 12,
                sha256: nil,
                pinned: false,
                pinnedOrder: nil,
                category: nil,
                sourceUrl: nil,
                sourceMetadata: nil,
                createdAt: "2026-01-10T00:00:00Z",
                updatedAt: "2026-01-10T00:00:00Z",
                deletedAt: nil
            ),
            job: IngestionJob(
                status: "processing",
                stage: "extracting",
                errorCode: nil,
                errorMessage: nil,
                userMessage: nil,
                progress: nil,
                attempts: 0,
                updatedAt: "2026-01-10T00:00:00Z"
            ),
            derivatives: [
                IngestionDerivative(
                    id: "file-1-d1",
                    kind: "text_original",
                    storageKey: "derivatives/file-1/text_original",
                    mime: "text/plain",
                    sizeBytes: 12
                )
            ],
            recommendedViewer: "text_original"
        )
        store.activeMeta = initialMeta
        store.applyListUpdate([
            IngestionStoreTestsSupport.makeItem(
                id: "file-1",
                status: "processing",
                stage: "extracting"
            )
        ], persist: true)

        store.applyFileJobEvent(
            RealtimePayload<FileJobRealtimeRecord>(
                eventType: .update,
                table: RealtimeTable.fileJobs,
                schema: "public",
                record: FileJobRealtimeRecord(
                    fileId: "file-1",
                    status: "ready",
                    stage: "ready",
                    errorCode: nil,
                    errorMessage: nil,
                    attempts: 1,
                    updatedAt: "2026-01-10T00:01:00Z"
                ),
                oldRecord: nil
            )
        )

        XCTAssertEqual(store.activeMeta?.job.status, "ready")
        XCTAssertEqual(store.activeMeta?.job.stage, "ready")
        XCTAssertEqual(store.activeMeta?.derivatives.map(\.id), ["file-1-d1"])
        let cached: IngestionMetaResponse? = cache.get(key: CacheKeys.ingestionMeta(fileId: "file-1"))
        XCTAssertEqual(cached?.job.status, "ready")
        XCTAssertEqual(cached?.derivatives.map(\.id), ["file-1-d1"])
    }
}
