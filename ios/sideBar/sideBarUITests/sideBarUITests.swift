//
//  sideBarUITests.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import Foundation
import XCTest

final class SideBarUITests: XCTestCase {

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
        let config = try loadLaunchConfig()
        let app = launchApp(with: config)
        attemptLogin(
            in: app,
            email: config.credentials.email,
            password: config.credentials.password
        )

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )
        let signInButton = resolveSignInButton(in: app)
        XCTAssertTrue(
            waitForNonExistence(of: signInButton, timeout: 10),
            "Sign In button remained visible after successful login."
        )
    }

    @MainActor
    func testLoginFailureShowsErrorAndStaysSignedOut() throws {
        let config = try loadLaunchConfig()
        let app = launchApp(with: config)
        attemptLogin(
            in: app,
            email: config.credentials.email,
            password: config.credentials.password + "x"
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
        let signInButton = resolveSignInButton(in: app)
        XCTAssertTrue(signInButton.exists, "Sign In button should remain visible on failed auth.")
        XCTAssertFalse(
            waitForSignedInHome(in: app, timeout: 5),
            "App unexpectedly navigated to signed-in home after failed auth."
        )
    }

    @MainActor
    func testSendMessageInSeededConversationShowsStreamingReply() throws {
        let config = try loadLaunchConfig()
        let app = try launchAuthenticatedApp(with: config)

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )

        let sendButton = openChatDetail(in: app)
        let messageField = resolveChatMessageField(in: app)
        XCTAssertTrue(
            waitForChatMessageRows(minimumCount: 1, in: app, timeout: 10),
            "Seeded conversation messages did not load before send."
        )
        let initialRowCount = chatMessageRowCount(in: app)

        let outboundMessage = "TC-UI-003 ping \(String(UUID().uuidString.prefix(8)))"
        messageField.tap()
        messageField.typeText(outboundMessage)
        XCTAssertTrue(sendButton.isEnabled, "Send message button should be enabled after typing.")
        sendButton.tap()

        XCTAssertTrue(
            waitForChatMessage(text: outboundMessage, in: app, timeout: 20),
            "Sent user message did not appear in chat."
        )
        XCTAssertTrue(
            waitForChatMessageRows(minimumCount: initialRowCount + 2, in: app, timeout: 45),
            "Expected assistant streamed reply row after sending."
        )
    }

    @MainActor
    func testCreateEditDeleteNoteInSeededAccount() throws {
        let config = try loadLaunchConfig()
        let app = try launchAuthenticatedApp(with: config)

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )

        let noteSuffix = String(UUID().uuidString.prefix(8))
        let noteTitle = "TC-UI-004 \(noteSuffix)"
        let renamedNoteTitle = "\(noteTitle) revised"

        openNotesTab(in: app)
        createNote(named: noteTitle, in: app)
        renameActiveNote(to: renamedNoteTitle, in: app)
        deleteActiveNote(in: app)

        XCTAssertTrue(
            waitForNonExistence(of: app.staticTexts[renamedNoteTitle], timeout: 20),
            "Renamed note remained visible after delete flow."
        )
    }

    @MainActor
    func openChatDetail(in app: XCUIApplication) -> XCUIElement {
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
        let chatDestination = resolvePrimaryNavigationElement(
            in: app,
            title: "Chat"
        )
        XCTAssertTrue(chatDestination.waitForExistence(timeout: 20), "Chat destination did not appear.")
        XCTAssertTrue(waitForHittable(chatDestination, timeout: 20), "Chat destination was not tappable.")
        chatDestination.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)

        let sendButton = app.buttons["Send message"]
        let seededConversationRow = resolveSeededConversationRow(in: app)
        if waitForHittable(seededConversationRow, timeout: 8) {
            seededConversationRow.tap()
            dismissSystemAlertsIfPresent(in: app, timeout: 6)
        } else if sendButton.waitForExistence(timeout: 8) {
            return sendButton
        }

        if !sendButton.exists, waitForHittable(chatDestination, timeout: 8) {
            chatDestination.tap()
            dismissSystemAlertsIfPresent(in: app, timeout: 6)
        }
        if sendButton.waitForExistence(timeout: 8) {
            return sendButton
        }

        let newChatButton = app.buttons["New chat"]
        if waitForHittable(newChatButton, timeout: 8) {
            newChatButton.tap()
        } else {
            XCTAssertTrue(
                waitForHittable(seededConversationRow, timeout: 8),
                "Seeded chat row did not appear in chat list."
            )
            seededConversationRow.tap()
        }

        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 20),
            "Send message button did not appear in chat detail."
        )
        return sendButton
    }

    func resolveChatMessageField(in app: XCUIApplication) -> XCUIElement {
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

    func loadLaunchConfig() throws -> UITestLaunchConfig {
        UITestLaunchConfig(
            credentials: try loadCredentials(),
            backend: try loadBackendConfig()
        )
    }

    private func loadCredentials() throws -> UITestCredentials {
        let environment = ProcessInfo.processInfo.environment
        if
            let email = environment[SideBarUITestConstants.uiTestEmailKey], !email.isEmpty,
            let password = environment[SideBarUITestConstants.uiTestPasswordKey], !password.isEmpty {
            return UITestCredentials(email: email, password: password)
        }

        let secretsFilePath = environment[SideBarUITestConstants.uiTestSecretsFileKey] ?? defaultSecretsFilePath()
        if let credentials = loadCredentialsFromSecretsFile(at: secretsFilePath) {
            return credentials
        }

        throw XCTSkip(
            "Missing UI test credentials. Set \(SideBarUITestConstants.uiTestEmailKey)/\(SideBarUITestConstants.uiTestPasswordKey) " +
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
        guard let values = loadSecretsValues(from: filePath) else { return nil }
        guard
            let email = values[SideBarUITestConstants.uiTestEmailKey], !email.isEmpty,
            let password = values[SideBarUITestConstants.uiTestPasswordKey], !password.isEmpty
        else {
            return nil
        }
        return UITestCredentials(email: email, password: password)
    }

    private func loadBackendConfig() throws -> UITestBackendConfig {
        let environment = ProcessInfo.processInfo.environment
        let secretsFilePath = environment[SideBarUITestConstants.uiTestSecretsFileKey] ?? defaultSecretsFilePath()
        let secretValues = loadSecretsValues(from: secretsFilePath) ?? [:]

        func resolveValue(
            primaryKey: String,
            fallbackKey: String
        ) -> String? {
            if let value = environment[primaryKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            if let value = environment[fallbackKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            if let value = secretValues[primaryKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            if let value = secretValues[fallbackKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
            return nil
        }

        guard
            let apiBaseUrl = resolveValue(
                primaryKey: SideBarUITestConstants.uiTestApiBaseUrlKey,
                fallbackKey: "API_BASE_URL"
            ),
            let supabaseUrl = resolveValue(
                primaryKey: SideBarUITestConstants.uiTestSupabaseUrlKey,
                fallbackKey: "SUPABASE_URL"
            ),
            let supabaseAnonKey = resolveValue(
                primaryKey: SideBarUITestConstants.uiTestSupabaseAnonKey,
                fallbackKey: "SUPABASE_ANON_KEY"
            )
        else {
            let requiredKeys = [
                SideBarUITestConstants.uiTestApiBaseUrlKey,
                SideBarUITestConstants.uiTestSupabaseUrlKey,
                SideBarUITestConstants.uiTestSupabaseAnonKey
            ].joined(separator: "/")
            throw XCTSkip(
                "Missing UI test backend configuration. Set " +
                "\(requiredKeys) " +
                "or API_BASE_URL/SUPABASE_URL/SUPABASE_ANON_KEY for UI tests."
            )
        }

        return UITestBackendConfig(
            apiBaseUrl: apiBaseUrl,
            supabaseUrl: supabaseUrl,
            supabaseAnonKey: supabaseAnonKey
        )
    }

    @MainActor
    func launchApp(with config: UITestLaunchConfig) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[SideBarUITestConstants.uiTestEmailKey] = config.credentials.email
        app.launchEnvironment[SideBarUITestConstants.uiTestPasswordKey] = config.credentials.password
        app.launchEnvironment["API_BASE_URL"] = config.backend.apiBaseUrl
        app.launchEnvironment["SUPABASE_URL"] = config.backend.supabaseUrl
        app.launchEnvironment["SUPABASE_ANON_KEY"] = config.backend.supabaseAnonKey
        app.launchEnvironment[SideBarUITestConstants.uiTestInMemoryAuthKey] = "1"
        app.launchEnvironment[SideBarUITestConstants.uiTestExposeChatScrollAnchorKey] = "1"
        app.launchEnvironment[SideBarUITestConstants.uiTestForceCompletedOnboardingKey] = "1"
        app.launch()
        dismissSystemAlertsIfPresent(in: app, timeout: 4)
        return app
    }

    func attemptLogin(
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

        let signInButton = resolveSignInButton(in: app)
        XCTAssertTrue(signInButton.exists, "Sign In button is missing.")
        signInButton.tap()
        dismissSystemAlertsIfPresent(in: app, timeout: 8)
    }

    func dismissSystemAlertsIfPresent(
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

    func waitForSignedInHome(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let indicators = [
            app.buttons["Settings"],
            app.buttons["Toggle sidebar"],
            app.tabBars.buttons["Notes"],
            app.tabBars.buttons["Tasks"],
            app.buttons["Notes"],
            app.buttons["Tasks"],
            app.buttons["Chat"]
        ]

        while Date() < deadline {
            if indicators.contains(where: { $0.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

}

enum SideBarUITestConstants {
    static let uiTestEmailKey = "SIDEBAR_UI_TEST_EMAIL"
    static let uiTestPasswordKey = "SIDEBAR_UI_TEST_PASSWORD"
    static let uiTestSecretsFileKey = "SIDEBAR_UI_TEST_SECRETS_FILE"
    static let uiTestInMemoryAuthKey = "SIDEBAR_UI_TEST_USE_IN_MEMORY_AUTH"
    static let uiTestExposeChatScrollAnchorKey = "SIDEBAR_UI_TEST_EXPOSE_CHAT_SCROLL_ANCHOR"
    static let uiTestForceCompletedOnboardingKey = "SIDEBAR_UI_TEST_FORCE_COMPLETED_ONBOARDING"
    static let uiTestChatConversationTitleKey = "SIDEBAR_UI_TEST_CHAT_CONVERSATION_TITLE"
    static let uiTestApiBaseUrlKey = "SIDEBAR_UI_TEST_API_BASE_URL"
    static let uiTestSupabaseUrlKey = "SIDEBAR_UI_TEST_SUPABASE_URL"
    static let uiTestSupabaseAnonKey = "SIDEBAR_UI_TEST_SUPABASE_ANON_KEY"
    static let uiTestAccessTokenKey = "SIDEBAR_UI_TEST_ACCESS_TOKEN"
    static let uiTestUserIdKey = "SIDEBAR_UI_TEST_USER_ID"
}

struct UITestCredentials {
    let email: String
    let password: String
}

struct UITestBackendConfig {
    let apiBaseUrl: String
    let supabaseUrl: String
    let supabaseAnonKey: String
}

struct UITestLaunchConfig {
    let credentials: UITestCredentials
    let backend: UITestBackendConfig
}
