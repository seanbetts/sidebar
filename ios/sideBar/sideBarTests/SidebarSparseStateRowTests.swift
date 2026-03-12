import XCTest
@testable import sideBar

final class SidebarSparseStateRowTests: XCTestCase {
    func testBodyUsesSelectableRowContainer() {
        let row = SidebarSparseStateRow(
            iconName: "globe",
            title: "No websites yet",
            subtitle: "Archived websites are still available below."
        )

        XCTAssertTrue(String(describing: type(of: row.body)).contains("SelectableRow"))
    }
}
