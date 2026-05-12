import XCTest
@testable import sideBar
import sideBarShared

final class EmptyStateContentTests: XCTestCase {
    func testAllTasksCompletedUsesSharedCopy() {
        let content = EmptyStateContent.allTasksCompleted()

        XCTAssertEqual(content.title, "All tasks completed")
        XCTAssertEqual(content.icon, AppIcon.State.successCircle)
        XCTAssertEqual(content.systemImage, "checkmark.circle")
    }

    func testNoResultsUsesSharedSearchCopy() {
        let content = EmptyStateContent.noResults()

        XCTAssertEqual(content.title, "No results")
        XCTAssertEqual(content.icon, AppIcon.Action.search)
        XCTAssertEqual(content.systemImage, "magnifyingglass")
    }

    func testNoContentYetKeepsExplicitTitleAndSubtitle() {
        let content = EmptyStateContent.noContentYet(
            title: "No files yet",
            subtitle: "Upload or create a file to get started.",
            systemImage: "folder"
        )

        XCTAssertEqual(content.title, "No files yet")
        XCTAssertEqual(content.subtitle, "Upload or create a file to get started.")
        XCTAssertEqual(content.icon, AppIcon.Content.folder)
        XCTAssertEqual(content.systemImage, "folder")
    }
}
