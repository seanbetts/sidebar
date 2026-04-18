import XCTest
@testable import sideBar

final class EmptyStateContentTests: XCTestCase {
    func testAllTasksCompletedUsesSharedCopy() {
        let content = EmptyStateContent.allTasksCompleted()

        XCTAssertEqual(content.title, "All tasks completed")
        XCTAssertEqual(content.systemImage, "checkmark.circle")
    }

    func testNoResultsUsesSharedSearchCopy() {
        let content = EmptyStateContent.noResults()

        XCTAssertEqual(content.title, "No results")
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
        XCTAssertEqual(content.systemImage, "folder")
    }
}
