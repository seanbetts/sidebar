//
//  sideBarUITestsLaunchTests.swift
//  sideBarUITests
//
//  Created by Sean Betts on 08/01/2026.
//

import XCTest

final class SideBarUITestsLaunchTests: XCTestCase {

    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        throw XCTSkip("Launch screenshot coverage is excluded from the default AppleUI smoke lane.")
    }
}
