import XCTest
@testable import sideBar
import sideBarShared

final class PendingWebsiteRowTests: XCTestCase {
    func testFailedPendingWebsiteRowUsesGenericWebsiteIcon() {
        let pending = WebsitesViewModel.PendingWebsiteItem(
            id: "pending-failed",
            title: "Reading...",
            domain: "example.com",
            url: "https://example.com/article",
            canonicalURL: "https://example.com/article",
            source: .directSave,
            status: .failed
        )

        let row = PendingWebsiteRow(
            pending: pending,
            useListStyling: true,
            onRetry: nil,
            onRemove: nil
        )

        XCTAssertEqual(row.leadingIcon, AppIcon.Content.websiteFallback)
    }
}
