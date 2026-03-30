import XCTest
@testable import sideBar

final class OnboardingViewLayoutTests: XCTestCase {
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
    func testSmallAccessoryFrameDoesNotCountAsSoftwareKeyboard() {
        let frame = CGRect(x: 0, y: 970, width: 1024, height: 54)

        XCTAssertEqual(
            OnboardingKeyboardMetrics.softwareKeyboardHeight(
                from: frame,
                screenMaxY: 1024
            ),
            0
        )
    }

    @MainActor
    func testFullKeyboardFrameCountsAsSoftwareKeyboard() {
        let frame = CGRect(x: 0, y: 700, width: 1024, height: 324)

        XCTAssertEqual(
            OnboardingKeyboardMetrics.softwareKeyboardHeight(
                from: frame,
                screenMaxY: 1024
            ),
            324
        )
    }

    @MainActor
    func testChromeLayoutIgnoresKeyboardSafeAreaAtRoot() {
        XCTAssertTrue(OnboardingChromeLayoutPolicy.rootIgnoresKeyboardSafeArea)
    }

    @MainActor
    func testLayoutModeStaysRegularWhenKeyboardIsVisible() {
        XCTAssertEqual(
            OnboardingChromeLayoutPolicy.layoutMode(isSoftwareKeyboardVisible: true),
            .regular
        )
    }

    @MainActor
    func testLayoutModeStaysRegularWhenKeyboardIsHidden() {
        XCTAssertEqual(
            OnboardingChromeLayoutPolicy.layoutMode(isSoftwareKeyboardVisible: false),
            .regular
        )
    }

    @MainActor
    func testOnboardingSheetCanvasUsesFixedIPadDesignSize() {
        XCTAssertEqual(
            OnboardingSheetCanvasLayout.canvasSize,
            CGSize(width: 420, height: 680)
        )
    }

    @MainActor
    func testOnboardingSheetCanvasUsesStableOuterPadding() {
        XCTAssertEqual(OnboardingSheetCanvasLayout.outerPadding, 24)
    }

    @MainActor
    func testRegularLayoutAddsMoreTopSpacing() {
        XCTAssertEqual(OnboardingLayoutMode.regular.topSpacing, 40)
    }

    @MainActor
    func testBackSwipePolicyAllowsLeadingHorizontalSwipeWhenBackIsAvailable() {
        XCTAssertTrue(
            OnboardingBackSwipePolicy.shouldNavigateBack(
                hasBackButton: true,
                startLocation: CGPoint(x: 20, y: 240),
                translation: CGSize(width: 120, height: 12)
            )
        )
    }

    @MainActor
    func testBackSwipePolicyRejectsSwipeWhenBackIsUnavailable() {
        XCTAssertFalse(
            OnboardingBackSwipePolicy.shouldNavigateBack(
                hasBackButton: false,
                startLocation: CGPoint(x: 20, y: 240),
                translation: CGSize(width: 120, height: 12)
            )
        )
    }

    @MainActor
    func testBackSwipePolicyRejectsShortSwipe() {
        XCTAssertFalse(
            OnboardingBackSwipePolicy.shouldNavigateBack(
                hasBackButton: true,
                startLocation: CGPoint(x: 20, y: 240),
                translation: CGSize(width: 60, height: 8)
            )
        )
    }

    @MainActor
    func testBackSwipePolicyRejectsMostlyVerticalSwipe() {
        XCTAssertFalse(
            OnboardingBackSwipePolicy.shouldNavigateBack(
                hasBackButton: true,
                startLocation: CGPoint(x: 20, y: 240),
                translation: CGSize(width: 120, height: 80)
            )
        )
    }

    @MainActor
    func testBackSwipePolicyRejectsSwipeAwayFromLeadingEdge() {
        XCTAssertFalse(
            OnboardingBackSwipePolicy.shouldNavigateBack(
                hasBackButton: true,
                startLocation: CGPoint(x: 140, y: 240),
                translation: CGSize(width: 120, height: 12)
            )
        )
    }

    @MainActor
    func testShouldShowOnboardingWhenSignedOutAndNotStarted() {
        let result = OnboardingPresentation.shouldPresent(
            authState: .signedOut,
            onboardingStatus: .notStarted,
            isTestingOnboarding: false
        )

#if os(macOS)
        XCTAssertFalse(result)
#else
        XCTAssertTrue(result)
#endif
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

#if os(macOS)
        XCTAssertFalse(result)
#else
        XCTAssertTrue(result)
#endif
    }

    @MainActor
    func testResetOnboardingLaunchArgumentIgnoredOnMac() {
        let result = OnboardingPresentation.isTestingOnboardingEnabled(arguments: ["-resetOnboarding"])

#if os(macOS)
        XCTAssertFalse(result)
#else
        XCTAssertTrue(result)
#endif
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

#if os(macOS)
        XCTAssertEqual(result, .login)
#else
        XCTAssertEqual(result, .onboardingBackdrop)
#endif
    }
}
