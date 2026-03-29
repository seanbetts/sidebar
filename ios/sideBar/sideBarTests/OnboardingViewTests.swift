import XCTest
#if canImport(UIKit)
import UIKit
import SwiftUI
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
    func testLayoutModeStaysRegularWhenKeyboardIsVisible() {
        XCTAssertEqual(
            OnboardingChromeLayoutPolicy.layoutMode(isSoftwareKeyboardVisible: true),
            .regular
        )
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

    @MainActor
    func testCreateAccountPasswordFieldUsesPasswordContentTypeAndLabelColorInDarkMode() throws {
        let viewModel = OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        )
        viewModel.currentStep = .createAccount
        viewModel.password = "Secret123!"

        let controller = mountCreateAccountStep(
            viewModel: viewModel,
            interfaceStyle: UIUserInterfaceStyle.dark
        )
        let secureField = try XCTUnwrap(
            findTextFields(in: controller.view).first(where: \.isSecureTextEntry)
        )
        let renderedColor = try XCTUnwrap(secureField.textColor)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(secureField.textContentType, .password)
        XCTAssertEqual(
            rgbaComponents(for: renderedColor),
            rgbaComponents(for: UIColor.label.resolvedColor(with: darkTraits))
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func mountCreateAccountStep(
        viewModel: OnboardingViewModel,
        interfaceStyle: UIUserInterfaceStyle,
        width: CGFloat = 390,
        height: CGFloat = 844
    ) -> UIHostingController<AnyView> {
        let controller = UIHostingController(
            rootView: AnyView(
                CreateAccountStepView(
                    viewModel: viewModel,
                    layoutMode: .regular,
                    bottomContentInset: 0
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = UIWindow(frame: frame)
        window.overrideUserInterfaceStyle = interfaceStyle
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return controller
    }

    private func findTextFields(in view: UIView) -> [UITextField] {
        var textFields = view.subviews.compactMap { $0 as? UITextField }
        for subview in view.subviews {
            textFields.append(contentsOf: findTextFields(in: subview))
        }
        return textFields
    }

    private func rgbaComponents(for color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue, alpha]
    }

#endif
}
