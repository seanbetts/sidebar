//
//  sideBarUITests+Helpers.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import Foundation
import XCTest

extension SideBarUITests {
    func resolveSeededConversationRow(in app: XCUIApplication) -> XCUIElement {
        let identifierPrefix = "chat-conversation-row-"
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let rows = app.descendants(matching: .any).matching(predicate)
        return rows.firstMatch
    }

    func seededConversationTitle() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let title = environment[SideBarUITestConstants.uiTestChatConversationTitleKey]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !title.isEmpty {
            return title
        }
        return "[seed:test-data] Onboarding flow review"
    }

    func loadSecretsValues(from filePath: String) -> [String: String]? {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        var values: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") || !trimmedLine.contains("=") {
                continue
            }
            let parts = trimmedLine.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = value
        }
        return values
    }

    func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testStreamingReplyKeepsBottomAnchorVisible() throws {
        let config = try loadLaunchConfig()
        let app = try launchAuthenticatedApp(with: config)

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )

        let sendButton = openChatDetail(in: app)
        let messageField = resolveChatMessageField(in: app)

        let outboundMessage = "TC-UI-006 stream test \(String(UUID().uuidString.prefix(8))). "
            + "Respond with 30 numbered lines, each line at least six words."
        messageField.tap()
        messageField.typeText(outboundMessage)
        XCTAssertTrue(sendButton.isEnabled, "Send message button should be enabled after typing.")
        sendButton.tap()

        let sentMessageText = app.staticTexts[outboundMessage]
        XCTAssertTrue(
            sentMessageText.waitForExistence(timeout: 20),
            "Sent user message did not appear in chat."
        )
        XCTAssertTrue(
            waitForAssistantReply(after: sentMessageText, in: app, timeout: 45),
            "Expected assistant streamed reply row after sending."
        )
        XCTAssertTrue(
            waitForBottomAnchorToRemainVisible(in: app, duration: 6),
            "Chat bottom anchor left the visible viewport during streaming updates."
        )
    }

    @MainActor
    func testIPadTasksWorkspaceDoesNotShowFloatingDock() throws {
        let config = try loadLaunchConfig()
        let app = try launchAuthenticatedApp(with: config)

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )

        if app.tabBars.buttons["Tasks"].exists {
            throw XCTSkip("This regression test targets iPad split layout only.")
        }

        let tasksSectionCandidates = [
            app.buttons["Tasks"],
            app.cells.staticTexts["Tasks"].firstMatch,
            app.staticTexts["Tasks"]
        ]
        var openedTasksSection = false
        for candidate in tasksSectionCandidates where waitForHittable(candidate, timeout: 8) {
            candidate.tap()
            openedTasksSection = true
            break
        }
        XCTAssertTrue(openedTasksSection, "Could not open Tasks section in iPad split layout.")

        let todaySelectionCandidates = [
            app.buttons["Today"],
            app.cells.staticTexts["Today"].firstMatch,
            app.staticTexts["Today"]
        ]
        var selectedToday = false
        for candidate in todaySelectionCandidates where waitForHittable(candidate, timeout: 8) {
            candidate.tap()
            selectedToday = true
            break
        }
        XCTAssertTrue(selectedToday, "Could not select Today tasks list in iPad split layout.")

        let floatingDock = app.otherElements["tasks-workspace-floating-dock"]
        XCTAssertTrue(
            waitForNonExistence(of: floatingDock, timeout: 5),
            "Tasks workspace floating dock should be hidden on iPad."
        )
    }

    @MainActor
    func openNotesTab(in app: XCUIApplication) {
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
        let notesDestination = resolvePrimaryNavigationElement(
            in: app,
            title: "Notes"
        )
        XCTAssertTrue(notesDestination.waitForExistence(timeout: 20), "Notes destination did not appear.")
        XCTAssertTrue(waitForHittable(notesDestination, timeout: 20), "Notes destination was not tappable.")
        notesDestination.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
    }

    func resolveSignInButton(in app: XCUIApplication) -> XCUIElement {
        let candidates = [
            app.buttons["Sign in"],
            app.buttons["Sign In"]
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return candidates[0]
    }

    func resolvePrimaryNavigationElement(
        in app: XCUIApplication,
        title: String
    ) -> XCUIElement {
        let candidates = [
            app.tabBars.buttons[title],
            app.buttons[title],
            app.cells.staticTexts[title].firstMatch,
            app.staticTexts[title]
        ]

        for candidate in candidates where candidate.exists {
            return candidate
        }

        return candidates[0]
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

    func waitForBottomAnchorToRemainVisible(
        in app: XCUIApplication,
        duration: TimeInterval
    ) -> Bool {
        let anchor = app.otherElements["chat-scroll-bottom-anchor"]
        guard anchor.waitForExistence(timeout: 10) else {
            return false
        }
        let deadline = Date().addingTimeInterval(duration)
        var observedSample = false
        while Date() < deadline {
            guard anchor.exists else {
                return false
            }
            observedSample = true
            if !anchor.isHittable {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return observedSample
    }
}
