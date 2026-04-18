import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class TasksWidgetConfigurationCatalogSyncTests: XCTestCase {
    func testSkipsWidgetCatalogSyncForEmptyStartupState() {
        XCTAssertFalse(
            TasksViewModel.shouldSyncWidgetConfigurationCatalog(
                projects: [],
                groups: []
            )
        )
    }

    func testSyncsWidgetCatalogWhenProjectsExist() {
        XCTAssertTrue(
            TasksViewModel.shouldSyncWidgetConfigurationCatalog(
                projects: [
                    TaskProject(
                        id: "project-1",
                        title: "Launch",
                        groupId: nil,
                        status: "active",
                        updatedAt: nil
                    )
                ],
                groups: []
            )
        )
    }

    func testSyncsWidgetCatalogWhenGroupsExist() {
        XCTAssertTrue(
            TasksViewModel.shouldSyncWidgetConfigurationCatalog(
                projects: [],
                groups: [
                    TaskGroup(
                        id: "group-1",
                        title: "Work",
                        updatedAt: nil
                    )
                ]
            )
        )
    }
}
