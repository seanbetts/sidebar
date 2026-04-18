import Foundation
import XCTest
import sideBarShared
@testable import sideBar

final class WidgetConfigCatalogPersistenceTests: XCTestCase {
    private func makeWidgetDataManager() -> WidgetDataManager {
        WidgetDataManager(
            userDefaults: UserDefaults(
                suiteName: "WidgetConfigurationCatalogPersistenceTests.\(UUID().uuidString)"
            )!
        )
    }

    func testTaskConfigurationCatalogPreservesExistingEntriesWhenIncomingUpdateIsEmpty() {
        let widgetDataManager = makeWidgetDataManager()

        widgetDataManager.updateTaskConfigurationCatalog(
            projects: [
                TaskProject(
                    id: "project-1",
                    title: "Launch",
                    groupId: "group-1",
                    status: "active",
                    updatedAt: nil
                )
            ],
            groups: [
                TaskGroup(
                    id: "group-1",
                    title: "Work",
                    updatedAt: nil
                )
            ]
        )

        widgetDataManager.updateTaskConfigurationCatalog(projects: [], groups: [])

        let catalog = widgetDataManager.loadTaskConfigurationCatalog()

        XCTAssertEqual(catalog.projects.map(\.id), ["project-1"])
        XCTAssertEqual(catalog.groups.map(\.id), ["group-1"])
    }
}
