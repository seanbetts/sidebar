import XCTest
@testable import sideBar
import sideBarShared

final class EmptyStateContentTests: XCTestCase {
    func testAllTasksCompletedUsesSharedCopy() {
        let content = EmptyStateContent.allTasksCompleted()

        XCTAssertEqual(content.title, "All tasks completed")
        XCTAssertEqual(content.icon, AppIcon.State.successCircle)
    }

    func testNoResultsUsesSharedSearchCopy() {
        let content = EmptyStateContent.noResults()

        XCTAssertEqual(content.title, "No results")
        XCTAssertEqual(content.icon, AppIcon.Action.search)
    }

    func testNoContentYetKeepsExplicitTitleSubtitleAndIcon() {
        let content = EmptyStateContent.noContentYet(
            title: "No files yet",
            subtitle: "Upload or create a file to get started.",
            icon: AppIcon.Domain.files
        )

        XCTAssertEqual(content.title, "No files yet")
        XCTAssertEqual(content.subtitle, "Upload or create a file to get started.")
        XCTAssertEqual(content.icon, AppIcon.Domain.files)
    }
}
