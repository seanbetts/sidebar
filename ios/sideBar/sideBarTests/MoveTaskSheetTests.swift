import XCTest
@testable import sideBar

final class MoveTaskSheetTests: XCTestCase {
    func testBuildMoveTaskSectionsPlacesNoGroupFirst() {
        let group = TaskGroup(id: "g1", title: "Work", updatedAt: nil)
        let groupedProject = TaskProject(
            id: "p1",
            title: "Roadmap",
            groupId: "g1",
            status: "active",
            updatedAt: nil
        )
        let orphanProject = TaskProject(
            id: "p2",
            title: "Personal",
            groupId: nil,
            status: "active",
            updatedAt: nil
        )

        let sections = buildMoveTaskSections(groups: [group], projects: [groupedProject, orphanProject])

        XCTAssertEqual(sections.map(\.id), ["none", "groups", "projects"])
        XCTAssertEqual(sections[0].destinations.map(\.id), [""])
        XCTAssertEqual(sections[1].destinations.map(\.id), ["g1"])
        XCTAssertEqual(sections[2].destinations.map(\.id), ["p1", "p2"])
    }
}
