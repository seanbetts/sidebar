import XCTest
@testable import sideBar

final class WebsitesPanelListSectionsTests: XCTestCase {
    func testSectionOrderShowsSparseStateThenArchiveWhenOnlyArchiveRemains() {
        XCTAssertEqual(
            WebsitesPanelView.listSectionLayout(
                panelState: .sparse,
                hasPinnedItems: false,
                hasMainItems: false,
                hasPendingItems: false
            ),
            [.sparseState, .archive]
        )
    }

    func testSectionOrderShowsPrimaryContentThenArchiveWhenItemsExist() {
        XCTAssertEqual(
            WebsitesPanelView.listSectionLayout(
                panelState: .content,
                hasPinnedItems: true,
                hasMainItems: false,
                hasPendingItems: false
            ),
            [.primaryContent, .archive]
        )
    }

    func testSwipeActionArchivesReturnsFalseForArchivedItem() {
        let item = makeItem(archived: true)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: true)

        XCTAssertFalse(result)
    }

    func testSwipeActionArchivesReturnsTrueForActiveItemWhenAllowed() {
        let item = makeItem(archived: false)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: true)

        XCTAssertTrue(result)
    }

    func testSwipeActionArchivesRespectsExplicitDisallow() {
        let item = makeItem(archived: false)

        let result = WebsitesPanelView.swipeActionArchives(item: item, allowArchive: false)

        XCTAssertFalse(result)
    }

    private func makeItem(archived: Bool) -> WebsiteItem {
        WebsiteItem(
            id: "site-1",
            title: "Example",
            url: "https://example.com",
            domain: "example.com",
            savedAt: nil,
            publishedAt: nil,
            pinned: false,
            pinnedOrder: nil,
            archived: archived,
            faviconUrl: nil,
            faviconR2Key: nil,
            youtubeTranscripts: nil,
            readingTime: nil,
            updatedAt: nil,
            lastOpenedAt: nil,
            deletedAt: nil
        )
    }
}
