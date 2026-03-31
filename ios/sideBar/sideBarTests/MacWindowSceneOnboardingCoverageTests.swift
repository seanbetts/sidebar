import XCTest

extension MacWindowSceneCoverageTests {
    func testMacContentViewDoesNotUseMacAutoOnboardingWindowRecovery() throws {
        let normalized = try contentViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("switchOnboardingPresentation.signedOutContent("))
        XCTAssertFalse(normalized.contains("scheduleMacAutomaticOnboardingPresentationIfNeeded()"))
        XCTAssertFalse(normalized.contains("waitingForVisibleHostWindow"))
        XCTAssertFalse(normalized.contains("autoPresentFallback"))
        XCTAssertFalse(normalized.contains("repairMacHostWindowForOnboardingPresentationIfNeeded"))
        XCTAssertFalse(normalized.contains("privatefuncmacRecoveryVisibleScreenFrame()->CGRect?"))
        XCTAssertFalse(normalized.contains("MacWindowFramePersistence.persistWindowFrameIfNeeded(window)"))
        XCTAssertFalse(normalized.contains("window.occlusionState.contains(.visible)"))
        XCTAssertFalse(normalized.contains("guardscenePhase==.activeelse{returnfalse}"))
    }
}
