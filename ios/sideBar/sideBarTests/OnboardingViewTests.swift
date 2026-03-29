import XCTest
#if canImport(UIKit)
import UIKit
#endif
@testable import sideBar

final class OnboardingViewTests: XCTestCase {
    @MainActor
    func testBottomChromeUsesOverlayPlacement() {
        XCTAssertEqual(OnboardingChromeLayoutPolicy.bottomAreaPlacement, .overlay)
    }

    @MainActor
    func testContentBottomInsetMatchesMeasuredBottomChromeHeight() {
        XCTAssertEqual(OnboardingChromeLayoutPolicy.contentBottomInset(for: 96), 96)
    }

    @MainActor
    func testContentBottomInsetAddsKeyboardHeightWhenPresent() {
        XCTAssertEqual(OnboardingChromeLayoutPolicy.contentBottomInset(for: 96, keyboardHeight: 240), 336)
    }

    @MainActor
    func testChromeLayoutIgnoresKeyboardSafeAreaAtRoot() {
        XCTAssertTrue(OnboardingChromeLayoutPolicy.rootIgnoresKeyboardSafeArea)
    }

    @MainActor
    func testShouldShowOnboardingWhenSignedOutAndNotStarted() {
        let result = OnboardingPresentation.shouldPresent(
            authState: .signedOut,
            onboardingStatus: .notStarted,
            isTestingOnboarding: false
        )

        XCTAssertTrue(result)
    }

    @MainActor
    func testShouldNotShowOnboardingWhenSignedOutButOnboardingStarted() {
        let result = OnboardingPresentation.shouldPresent(
            authState: .signedOut,
            onboardingStatus: .inProgress,
            isTestingOnboarding: false
        )

        XCTAssertFalse(result)
    }

    @MainActor
    func testShouldNotShowOnboardingWhenSignedIn() {
        let result = OnboardingPresentation.shouldPresent(
            authState: .active,
            onboardingStatus: .notStarted,
            isTestingOnboarding: false
        )

        XCTAssertFalse(result)
    }

    @MainActor
    func testResetOnboardingForceShowsOnboarding() {
        let result = OnboardingPresentation.shouldPresent(
            authState: .active,
            onboardingStatus: .completed,
            isTestingOnboarding: true
        )

        XCTAssertTrue(result)
    }

    @MainActor
    func testManualStartAllowedWhenSignedOut() {
        let result = OnboardingPresentation.shouldAllowManualStart(authState: .signedOut)

        XCTAssertTrue(result)
    }

    @MainActor
    func testManualStartNotAllowedWhenSignedIn() {
        let result = OnboardingPresentation.shouldAllowManualStart(authState: .active)

        XCTAssertFalse(result)
    }

    @MainActor
    func testSignedOutContentIsLoginWhenOnboardingHidden() {
        let result = OnboardingPresentation.signedOutContent(
            authState: .signedOut,
            isOnboardingPresented: false
        )

        XCTAssertEqual(result, .login)
    }

    @MainActor
    func testSignedOutContentUsesBackdropWhenOnboardingShown() {
        let result = OnboardingPresentation.signedOutContent(
            authState: .signedOut,
            isOnboardingPresented: true
        )

        XCTAssertEqual(result, .onboardingBackdrop)
    }

#if canImport(UIKit)
    @MainActor
    func testPresentationStyleIsFullScreenCoverOnPhone() {
        let style = OnboardingPresentation.style(for: .phone)

        XCTAssertEqual(style, .fullScreenCover)
    }

    @MainActor
    func testPresentationStyleIsSheetOnPad() {
        let style = OnboardingPresentation.style(for: .pad)

        XCTAssertEqual(style, .sheet)
    }
#endif
}
