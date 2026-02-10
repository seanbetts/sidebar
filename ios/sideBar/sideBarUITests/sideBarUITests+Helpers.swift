//
//  sideBarUITests+Helpers.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import XCTest

extension SideBarUITests {
    @MainActor
    func openNotesTab(in app: XCUIApplication) {
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
        let notesTab = app.tabBars.buttons["Notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 20), "Notes tab did not appear.")
        XCTAssertTrue(waitForHittable(notesTab, timeout: 20), "Notes tab was not tappable.")
        notesTab.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
    }

    @MainActor
    func createNote(named title: String, in app: XCUIApplication) {
        let addNoteButton = app.buttons["Add note"]
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 20), "Add note button did not appear.")
        XCTAssertTrue(waitForHittable(addNoteButton, timeout: 10), "Add note button was not tappable.")
        addNoteButton.tap()

        let titleField = app.textFields["Note title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "New note title field did not appear.")
        titleField.tap()
        titleField.typeText(title)

        let createButton = app.buttons["Create"]
        XCTAssertTrue(waitForHittable(createButton, timeout: 10), "Create note button was not tappable.")
        createButton.tap()

        let titleText = app.staticTexts[title]
        let noteOptionsButton = app.buttons["Note options"]
        XCTAssertTrue(
            waitForAny([titleText, noteOptionsButton], timeout: 20),
            "Created note did not appear in notes UI."
        )
    }

    @MainActor
    func renameActiveNote(to newTitle: String, in app: XCUIApplication) {
        app.tap()
        let noteOptionsButton = app.buttons["Note options"]
        XCTAssertTrue(
            waitForHittable(noteOptionsButton, timeout: 20),
            "Note options button did not become tappable for rename."
        )
        noteOptionsButton.tap()

        let renameAction = app.buttons["Rename"]
        XCTAssertTrue(waitForHittable(renameAction, timeout: 10), "Rename action did not appear.")
        renameAction.tap()

        let renameField = app.textFields["Note name"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 10), "Rename note field did not appear.")
        renameField.tap()
        renameField.typeText(" revised")

        let renameButton = app.buttons["Rename"]
        XCTAssertTrue(waitForHittable(renameButton, timeout: 10), "Rename confirmation button did not appear.")
        renameButton.tap()

        XCTAssertTrue(
            app.staticTexts[newTitle].waitForExistence(timeout: 20),
            "Renamed note title did not appear in notes UI."
        )
    }

    @MainActor
    func deleteActiveNote(in app: XCUIApplication) {
        app.tap()
        let noteOptionsButton = app.buttons["Note options"]
        XCTAssertTrue(
            waitForHittable(noteOptionsButton, timeout: 20),
            "Note options button did not become tappable."
        )
        noteOptionsButton.tap()

        let deleteAction = app.buttons["Delete"]
        XCTAssertTrue(waitForHittable(deleteAction, timeout: 10), "Delete menu action did not appear.")
        deleteAction.tap()

        let deleteAlert = app.alerts["Delete note"]
        if deleteAlert.waitForExistence(timeout: 10) {
            let confirmDeleteButton = deleteAlert.buttons["Delete"]
            XCTAssertTrue(
                waitForHittable(confirmDeleteButton, timeout: 10),
                "Delete confirmation button did not appear."
            )
            confirmDeleteButton.tap()
            return
        }

        // Fallback for platforms where delete appears as a confirmation dialog without alert wrapper.
        let fallbackDelete = app.buttons["Delete"]
        XCTAssertTrue(waitForHittable(fallbackDelete, timeout: 10), "Fallback delete button did not appear.")
        fallbackDelete.tap()
    }

    func waitForAny(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if elements.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && element.isHittable
    }

    func waitForAssistantReply(
        after sentMessage: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasAssistantLabelBelowMessage(sentMessage, in: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return hasAssistantLabelBelowMessage(sentMessage, in: app)
    }

    func hasAssistantLabelBelowMessage(
        _ sentMessage: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        guard sentMessage.exists else {
            return false
        }
        let baselineY = sentMessage.frame.maxY
        let assistantLabels = app.staticTexts.matching(NSPredicate(format: "label == %@", "sideBar"))
        for index in 0..<assistantLabels.count {
            let label = assistantLabels.element(boundBy: index)
            if label.exists, label.frame.minY >= baselineY - 1 {
                return true
            }
        }
        return false
    }
}
