//
//  sideBarUITests.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import Foundation
import XCTest

final class SideBarUITests: XCTestCase {
    private let uiTestEmailKey = "SIDEBAR_UI_TEST_EMAIL"
    private let uiTestPasswordKey = "SIDEBAR_UI_TEST_PASSWORD"
    private let uiTestSecretsFileKey = "SIDEBAR_UI_TEST_SECRETS_FILE"
    private let uiTestInMemoryAuthKey = "SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH"
    private let uiTestChatConversationTitleKey = "SIDEBAR_UI_TEST_CHAT_CONVERSATION_TITLE"

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            let buttonLabels = [
                "Continue",
                "Allow",
                "OK",
                "Don’t Allow",
                "Don't Allow",
                "Allow While Using App",
                "Allow Once",
                "Not Now",
                "Don't Save",
                "Don’t Save",
                "Save"
            ]
            for label in buttonLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    @MainActor
    func testLoginSuccessNavigatesToSignedInHome() throws {
        let credentials = try loadCredentials()
        let app = launchApp(with: credentials)
        attemptLogin(
            in: app,
            email: credentials.email,
            password: credentials.password
        )

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(
            waitForNonExistence(of: signInButton, timeout: 10),
            "Sign In button remained visible after successful login."
        )
    }

    @MainActor
    func testLoginFailureShowsErrorAndStaysSignedOut() throws {
        let credentials = try loadCredentials()
        let app = launchApp(with: credentials)
        attemptLogin(
            in: app,
            email: credentials.email,
            password: credentials.password + "x"
        )

        let authError = app.otherElements["Error"]
        let invalidCredentialsText = app.staticTexts["Email or password is incorrect."]
        XCTAssertTrue(
            waitForAny(
                [authError, invalidCredentialsText],
                timeout: 20
            ),
            "Expected auth error did not appear for invalid credentials."
        )
        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Sign In button should remain visible on failed auth.")
        XCTAssertFalse(
            waitForSignedInHome(in: app, timeout: 5),
            "App unexpectedly navigated to signed-in home after failed auth."
        )
    }

    @MainActor
    func testSendMessageInSeededConversationShowsStreamingReply() throws {
        let credentials = try loadCredentials()
        let app = launchApp(with: credentials)
        attemptLogin(
            in: app,
            email: credentials.email,
            password: credentials.password
        )

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )

        let sendButton = openChatDetail(in: app)
        let messageField = resolveChatMessageField(in: app)

        let outboundMessage = "TC-UI-003 ping \(String(UUID().uuidString.prefix(8)))"
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
    }

    @MainActor
    private func openChatDetail(in app: XCUIApplication) -> XCUIElement {
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
        let chatTab = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 20), "Chat tab did not appear.")
        XCTAssertTrue(waitForHittable(chatTab, timeout: 20), "Chat tab was not tappable.")
        chatTab.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)

        let sendButton = app.buttons["Send message"]
        if sendButton.waitForExistence(timeout: 8) {
            return sendButton
        }

        if !chatTab.isSelected, waitForHittable(chatTab, timeout: 8) {
            chatTab.tap()
            dismissSystemAlertsIfPresent(in: app, timeout: 6)
        }
        if sendButton.waitForExistence(timeout: 8) {
            return sendButton
        }

        let newChatButton = app.buttons["New chat"]
        if waitForHittable(newChatButton, timeout: 8) {
            newChatButton.tap()
        } else {
            let conversationTitle = seededConversationTitle()
            let conversationRow = app.staticTexts[conversationTitle]
            if waitForHittable(conversationRow, timeout: 8) {
                conversationRow.tap()
            } else {
                let anyConversationCell = app.cells.firstMatch
                if waitForHittable(anyConversationCell, timeout: 8) {
                    anyConversationCell.tap()
                } else {
                    XCTFail("Could not reach chat detail view from Chat tab.")
                }
            }
        }

        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 20),
            "Send message button did not appear in chat detail."
        )
        return sendButton
    }

    private func resolveChatMessageField(in app: XCUIApplication) -> XCUIElement {
        let labeledMessageField = app.textViews["Message"]
        if labeledMessageField.waitForExistence(timeout: 6) {
            return labeledMessageField
        }

        let anyTextView = app.textViews.firstMatch
        if anyTextView.waitForExistence(timeout: 6) {
            return anyTextView
        }

        let fallbackMessageField = app.otherElements["Message"]
        XCTAssertTrue(
            fallbackMessageField.waitForExistence(timeout: 10),
            "Chat input field did not appear."
        )
        return fallbackMessageField
    }

    private struct UITestCredentials {
        let email: String
        let password: String
    }

    private func loadCredentials() throws -> UITestCredentials {
        let environment = ProcessInfo.processInfo.environment
        if
            let email = environment[uiTestEmailKey], !email.isEmpty,
            let password = environment[uiTestPasswordKey], !password.isEmpty {
            return UITestCredentials(email: email, password: password)
        }

        let secretsFilePath = environment[uiTestSecretsFileKey] ?? defaultSecretsFilePath()
        if let credentials = loadCredentialsFromSecretsFile(at: secretsFilePath) {
            return credentials
        }

        throw XCTSkip(
            "Missing UI test credentials. Set \(uiTestEmailKey)/\(uiTestPasswordKey) " +
            "or add .ui-test-secrets.local at \(defaultSecretsFilePath())."
        )
    }

    private func defaultSecretsFilePath() -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".ui-test-secrets.local")
            .path
    }

    private func loadCredentialsFromSecretsFile(
        at filePath: String
    ) -> UITestCredentials? {
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
        guard
            let email = values[uiTestEmailKey], !email.isEmpty,
            let password = values[uiTestPasswordKey], !password.isEmpty
        else {
            return nil
        }
        return UITestCredentials(email: email, password: password)
    }

    @MainActor
    private func launchApp(with credentials: UITestCredentials) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[uiTestEmailKey] = credentials.email
        app.launchEnvironment[uiTestPasswordKey] = credentials.password
        app.launchEnvironment[uiTestInMemoryAuthKey] = "1"
        app.launch()
        dismissSystemAlertsIfPresent(in: app, timeout: 4)
        return app
    }

    private func attemptLogin(
        in app: XCUIApplication,
        email: String,
        password: String
    ) {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(
            emailField.waitForExistence(timeout: 20),
            "Login screen did not appear."
        )
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(
            passwordField.waitForExistence(timeout: 10),
            "Password field did not appear."
        )
        passwordField.tap()
        passwordField.typeText(password)

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Sign In button is missing.")
        signInButton.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
    }

    private func seededConversationTitle() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let title = environment[uiTestChatConversationTitleKey]?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !title.isEmpty {
            return title
        }
        return "[seed:test-data] Onboarding flow review"
    }

    private func dismissSystemAlertsIfPresent(
        in app: XCUIApplication,
        timeout: TimeInterval = 2
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let buttonLabels = [
            "Not Now",
            "Don't Save",
            "Don’t Save",
            "Save Password",
            "Save",
            "Allow",
            "Allow Once",
            "Allow While Using App",
            "OK",
            "Continue",
            "Don’t Allow",
            "Don't Allow"
        ]

        while Date() < deadline {
            app.activate()
            app.tap()

            let dismissedInApp = tapFirstExistingButton(in: app, labels: buttonLabels)
            let dismissedInSpringboard = tapFirstExistingButton(
                in: springboard,
                labels: buttonLabels
            )
            if !dismissedInApp, !dismissedInSpringboard {
                let savePasswordVisible = app.sheets["Save Password?"].exists
                    || app.staticTexts["Save Password?"].exists
                    || springboard.sheets["Save Password?"].exists
                    || springboard.staticTexts["Save Password?"].exists
                if !savePasswordVisible {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func tapFirstExistingButton(
        in application: XCUIApplication,
        labels: [String]
    ) -> Bool {
        for label in labels {
            let candidates = [
                application.alerts.buttons[label].firstMatch,
                application.sheets.buttons[label].firstMatch,
                application.buttons[label].firstMatch
            ]
            for button in candidates where button.exists {
                if button.isHittable {
                    button.tap()
                } else {
                    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
                return true
            }
        }
        return false
    }

    private func waitForSignedInHome(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let indicators = [
            app.buttons["Settings"],
            app.buttons["Toggle sidebar"],
            app.tabBars.buttons["Notes"],
            app.tabBars.buttons["Tasks"]
        ]

        while Date() < deadline {
            if indicators.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForAny(
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

    private func waitForHittable(
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

}

private extension SideBarUITests {
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
