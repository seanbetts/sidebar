import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class IngestionStoreFilteringAndMetaTests: XCTestCase {
    func testLoadListFiltersTranscriptRowsFromCacheBeforeRefresh() async throws {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        cache.set(
            key: CacheKeys.ingestionList,
            value: IngestionListResponse(
                items: [
                    IngestionStoreTestsSupport.makeItem(id: "keep-cached"),
                    IngestionStoreTestsSupport.makeItem(
                        id: "drop-cached-transcript",
                        filename: "YouTube transcript",
                        sourceMetadata: ["website_transcript": AnyCodable(true)]
                    )
                ]
            ),
            ttlSeconds: 600
        )
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )

        try await store.loadList(force: false)

        XCTAssertEqual(store.items.map(\.file.id), ["keep-cached"])
    }

    func testApplySyncFileInfersRecommendedViewerWhenMissing() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )
        let file = IngestedFileMeta(
            id: "f-sync",
            filenameOriginal: "sync.pdf",
            path: "/sync.pdf",
            mimeOriginal: "application/pdf",
            sizeBytes: 12,
            sha256: nil,
            pinned: true,
            pinnedOrder: 0,
            category: nil,
            sourceUrl: nil,
            sourceMetadata: nil,
            createdAt: "2024-01-01T12:00:00Z",
            updatedAt: "2024-01-01T12:00:00Z",
            deletedAt: nil
        )

        store.applySyncFile(file)

        XCTAssertEqual(store.items.first?.recommendedViewer, "viewer_pdf")
    }

    func testApplyMetaUpdateSwitchesActiveMetaWhenFileIDChangesButShapeMatches() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )
        let first = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "processing",
            stage: "extracting",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )
        let second = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-2",
            status: "processing",
            stage: "extracting",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )

        store.applyMetaUpdate(first, persist: false)
        store.applyMetaUpdate(second, persist: false)

        XCTAssertEqual(store.activeMeta?.file.id, "file-2")
    }

    func testApplyMetaUpdateUpdatesWhenRecommendedViewerChanges() async {
        let cache = TestCacheClient()
        let defaults = IngestionStoreTestsSupport.makeDefaults()
        let store = IngestionStore(
            api: IngestionStoreTestsSupport.MockIngestionAPI(),
            cache: cache,
            userDefaults: defaults
        )
        let initial = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "ready",
            stage: "ready",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: nil
        )
        let updated = IngestionStoreTestsSupport.makeMeta(
            fileID: "file-1",
            status: "ready",
            stage: "ready",
            updatedAt: "2026-01-10T00:00:00Z",
            recommendedViewer: "text_original"
        )

        store.applyMetaUpdate(initial, persist: false)
        store.applyMetaUpdate(updated, persist: false)

        XCTAssertEqual(store.activeMeta?.recommendedViewer, "text_original")
    }
}
