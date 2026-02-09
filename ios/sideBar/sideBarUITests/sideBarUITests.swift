//
//  sideBarUITests.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import XCTest

final class SideBarUITests: XCTestCase {
    private let uiTestEmailKey = "SIDEBAR_UI_TEST_EMAIL"
    private let uiTestPasswordKey = "SIDEBAR_UI_TEST_PASSWORD"

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
                "Not Now"
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
        let app = XCUIApplication()
        app.launchEnvironment[uiTestEmailKey] = credentials.email
        app.launchEnvironment[uiTestPasswordKey] = credentials.password
        app.launch()
        dismissSystemAlertsIfPresent(in: app)

        let emailField = app.textFields["Email"]
        XCTAssertTrue(
            emailField.waitForExistence(timeout: 20),
            "Login screen did not appear."
        )
        emailField.tap()
        emailField.typeText(credentials.email)

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(
            passwordField.waitForExistence(timeout: 10),
            "Password field did not appear."
        )
        passwordField.tap()
        passwordField.typeText(credentials.password)

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.exists, "Sign In button is missing.")
        signInButton.tap()
        dismissSystemAlertsIfPresent(in: app)

        XCTAssertTrue(
            waitForSignedInHome(in: app, timeout: 45),
            "Signed-in shell did not appear after login."
        )
        XCTAssertTrue(
            waitForNonExistence(of: signInButton, timeout: 10),
            "Sign In button remained visible after successful login."
        )
    }

    private struct UITestCredentials {
        let email: String
        let password: String
    }

    private func loadCredentials() throws -> UITestCredentials {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment[uiTestEmailKey], !email.isEmpty else {
            throw XCTSkip("Missing \(uiTestEmailKey) in test environment.")
        }
        guard let password = environment[uiTestPasswordKey], !password.isEmpty else {
            throw XCTSkip("Missing \(uiTestPasswordKey) in test environment.")
        }
        return UITestCredentials(email: email, password: password)
    }

    private func dismissSystemAlertsIfPresent(in app: XCUIApplication) {
        app.tap()
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
}
