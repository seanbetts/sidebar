import XCTest
@testable import sideBar

final class WebsitesPendingStatusLabelTests: XCTestCase {
    func testStatusLabelUsesWatchingForYouTubeReadingItems() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-yt",
            title: "Watching...",
            domain: "youtube.com",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            canonicalURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            source: .directSave,
            status: .reading
        )

        XCTAssertEqual(pending.statusLabel, "Watching...")
    }

    func testStatusLabelUsesReadingForNonYouTubeReadingItems() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-web",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com/article",
            canonicalURL: "https://example.com/article",
            source: .directSave,
            status: .reading
        )

        XCTAssertEqual(pending.statusLabel, "Reading...")
    }

    func testStatusLabelPreservesNonReadingStatesForYouTubeItems() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-yt-queued",
            title: "Watching...",
            domain: "youtube.com",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            canonicalURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            source: .directSave,
            status: .queued
        )

        XCTAssertEqual(pending.statusLabel, "Queued")
    }

    func testStatusLabelUsesSavedForLaterForQueuedShareRows() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-queued-share",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com/article",
            canonicalURL: "https://example.com/article",
            source: .queuedShare,
            status: .queued
        )

        XCTAssertEqual(pending.statusLabel, "Saved for later")
    }

    func testProgressMessageUsesQueuedToReadForPendingWebsite() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-queued",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com/article",
            canonicalURL: "https://example.com/article",
            source: .directSave,
            status: .queued
        )

        XCTAssertEqual(pending.progressMessage, "Queued to read...")
    }

    func testProgressMessageUsesQueuedToWatchForPendingYouTubeSave() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-yt-queued",
            title: "Watching...",
            domain: "youtube.com",
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            canonicalURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            source: .directSave,
            status: .queued
        )

        XCTAssertEqual(pending.progressMessage, "Queued to watch...")
    }
}
