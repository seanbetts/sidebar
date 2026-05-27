import XCTest
import CoreSpotlight
@testable import sideBar

@MainActor
final class SpotlightIndexerTests: XCTestCase {
    func testDeepLinkURLMapsTaskIdentifiersToTasksSection() {
        let url = SpotlightIndexer.deepLinkURL(from: "task:task-123")

        XCTAssertEqual(url, URL(string: "sidebar://tasks"))
    }

    func testDeepLinkURLRejectsEmptyTaskIdentifier() {
        XCTAssertNil(SpotlightIndexer.deepLinkURL(from: "task:"))
    }

    func testNoteIndexingExcludesBodyContentAndPathKeywords() async throws {
        let recordingIndex = RecordingSearchableIndex()
        let indexer = SpotlightIndexer(index: recordingIndex)
        let note = SpotlightNote(
            path: "Private/Finance/plan.md",
            name: "Quarterly Plan",
            content: "Sensitive note body that should not be searchable",
            modified: nil
        )

        await indexer.indexNote(note)

        let attributes = try XCTUnwrap(recordingIndex.indexedItems.first?.attributeSet)
        XCTAssertEqual(attributes.title, "Quarterly Plan")
        XCTAssertNil(attributes.contentDescription)
        XCTAssertEqual(attributes.textContent, "Quarterly Plan")
        XCTAssertEqual(attributes.keywords, ["Quarterly", "Plan"])
    }

    func testTaskIndexingExcludesTaskNotes() async throws {
        let recordingIndex = RecordingSearchableIndex()
        let indexer = SpotlightIndexer(index: recordingIndex)
        let task = SpotlightTask(
            id: "task-123",
            title: "Renew contract",
            notes: "Sensitive negotiation details",
            status: "open",
            deadline: "2026-06-01"
        )

        await indexer.indexTask(task)

        let attributes = try XCTUnwrap(recordingIndex.indexedItems.first?.attributeSet)
        XCTAssertEqual(attributes.title, "Renew contract")
        XCTAssertEqual(attributes.textContent, "Renew contract open 2026-06-01")
        XCTAssertFalse(attributes.textContent?.contains("Sensitive negotiation details") ?? false)
    }

    func testWebsiteIndexingExcludesFullURLPathAndQuery() async throws {
        let recordingIndex = RecordingSearchableIndex()
        let indexer = SpotlightIndexer(index: recordingIndex)
        let website = SpotlightWebsite(
            id: "site-123",
            title: "Acme Dashboard",
            url: "https://example.com/private/path?token=secret",
            domain: "example.com",
            savedAt: nil
        )

        await indexer.indexWebsite(website)

        let attributes = try XCTUnwrap(recordingIndex.indexedItems.first?.attributeSet)
        XCTAssertEqual(attributes.title, "Acme Dashboard")
        XCTAssertEqual(attributes.contentDescription, "example.com")
        XCTAssertEqual(attributes.url?.absoluteString, "https://example.com")
        XCTAssertEqual(attributes.textContent, "Acme Dashboard example.com")
        XCTAssertFalse(attributes.textContent?.contains("/private/path") ?? false)
        XCTAssertFalse(attributes.textContent?.contains("token=secret") ?? false)
    }
}

private final class RecordingSearchableIndex: CSSearchableIndex {
    private(set) var indexedItems: [CSSearchableItem] = []

    override init() {
        super.init(name: "RecordingSearchableIndex.\(UUID().uuidString)")
    }

    override func indexSearchableItems(
        _ items: [CSSearchableItem],
        completionHandler: (((any Error)?) -> Void)? = nil
    ) {
        indexedItems.append(contentsOf: items)
        completionHandler?(nil)
    }
}
