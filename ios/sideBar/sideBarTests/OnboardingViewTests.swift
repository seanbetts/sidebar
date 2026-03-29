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
    func testTransitionContainerUsesDirectionalForwardStyleWhenReduceMotionIsOff() {
        XCTAssertEqual(
            OnboardingStepTransitionContainer<EmptyView>.transitionStyle(
                reduceMotion: false,
                direction: .forward
            ),
            .movingForward
        )
    }

    @MainActor
    func testTransitionContainerUsesSlideOnlyRecipeWhenReduceMotionIsOff() {
        XCTAssertEqual(
            OnboardingStepTransitionContainer<EmptyView>.transitionRecipe(
                reduceMotion: false,
                direction: .forward
            ),
            .slideForward
        )
        XCTAssertEqual(
            OnboardingStepTransitionContainer<EmptyView>.transitionRecipe(
                reduceMotion: false,
                direction: .backward
            ),
            .slideBackward
        )
    }

    @MainActor
    func testTransitionContainerUsesReducedMotionFallback() {
        XCTAssertEqual(
            OnboardingStepTransitionContainer<EmptyView>.transitionStyle(
                reduceMotion: true,
                direction: .backward
            ),
            .reducedMotion
        )
    }

    @MainActor
    func testTransitionContainerClipsAnimatedContentToViewport() {
        XCTAssertTrue(OnboardingStepTransitionViewportPolicy.clipsAnimatedContent)
    }

    @MainActor
    func testPermissionActionStateShowsContinueOnlyForGrantedResolvedPermission() {
        XCTAssertEqual(
            OnboardingPermissionActionState.resolve(
                isResolved: true,
                permissionState: .granted
            ),
            OnboardingPermissionActionState(
                primaryTitle: "Continue",
                hidesSecondaryAction: true
            )
        )
    }

    @MainActor
    func testPermissionActionStateKeepsEnableForSkippedResolvedPermission() {
        XCTAssertEqual(
            OnboardingPermissionActionState.resolve(
                isResolved: true,
                permissionState: .notAsked
            ),
            OnboardingPermissionActionState(
                primaryTitle: "Enable",
                hidesSecondaryAction: false
            )
        )
    }

    @MainActor
    func testWelcomeSecondaryActionUsesPlainTextLinkPresentation() throws {
        let normalized = try onboardingBottomAreaViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "secondaryTextLink(\"Alreadyhaveanaccount?SignIn\",action:routeToSignIn)"
            )
        )
        XCTAssertTrue(normalized.contains(".buttonStyle(.plain)"))
    }

    @MainActor
    func testVerifyEmailResendActionUsesPlainTextLinkPresentation() throws {
        let normalized = try verifyEmailStepViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "Button(resendCooldown>0?\"Resendcode(\\(resendCooldown)s)\":\"Resendcode\"){resendCode()}.buttonStyle(.plain)"
            )
        )
    }

    @MainActor
    func testVerifyEmailStepDoesNotAddCustomFocusOverlayStroke() throws {
        let normalized = try verifyEmailStepViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains(".overlay("))
        XCTAssertFalse(normalized.contains(".stroke(focusedIndex==index?Color.primary:Color.clear,lineWidth:2)"))
    }

    @MainActor
    func testChooseProviderCardsUseMutedBackgroundFill() throws {
        let normalized = try chooseProviderStepViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".background(DesignTokens.Colors.muted)"))
        XCTAssertFalse(normalized.contains(".background(DesignTokens.Colors.surface)"))
    }

    @MainActor
    func testNotificationsPermissionStepDoesNotUseSkippedCopy() throws {
        let normalized = try notificationsPermissionStepViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("return\"NotificationsEnabled\""))
        XCTAssertTrue(normalized.contains("return\"StayInTheLoop\""))
        XCTAssertTrue(normalized.contains("return\"CheckingNotificationStatus\""))
        XCTAssertFalse(normalized.contains("NotificationsSkipped"))
    }

    @MainActor
    func testNotificationsPermissionActionWaitsForRefreshBeforeShowingPrompt() throws {
        let normalized = try onboardingBottomAreaViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("isRefreshing:viewModel.isRefreshingNotificationsPermissionState"))
        XCTAssertTrue(normalized.contains("showsProgress:viewModel.isLoading||isRefreshing"))
        XCTAssertTrue(normalized.contains(".disabled(viewModel.isLoading||isRefreshing)"))
        XCTAssertTrue(normalized.contains("ifactionState.hidesSecondaryAction||isRefreshing"))
    }

    @MainActor
    func testBackButtonUsesPlainPresentation() throws {
        let normalized = try onboardingViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("Button(action:{viewModel.goBack()}"))
        XCTAssertTrue(normalized.contains(".buttonStyle(.plain)"))
    }

    @MainActor
    func testOnboardingViewOnlyAllowsDismissDuringMacTermination() throws {
        let normalized = try onboardingViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains(".interactiveDismissDisabled(shouldDisableInteractiveDismiss)"))
        XCTAssertTrue(normalized.contains("privatevarshouldDisableInteractiveDismiss:Bool"))
        XCTAssertTrue(normalized.contains("#ifos(macOS)!allowsTerminationDismiss#elsetrue#endif"))
        XCTAssertTrue(
            normalized.contains(
                ".onReceive(NotificationCenter.default.publisher(for:.macAppTerminationRequested)){_inallowsTerminationDismiss=true}"
            )
        )
    }

    @MainActor
    func testOnboardingViewCanRenderLocationStep() {
        XCTAssertEqual(
            OnboardingView.contentKind(for: .locationPermission),
            .locationPermission
        )
    }

    @MainActor
    func testOnboardingViewCanRenderNotificationsStep() {
        XCTAssertEqual(
            OnboardingView.contentKind(for: .notificationsPermission),
            .notificationsPermission
        )
    }

    @MainActor
    func testOnboardingViewRoutesFinalStepThroughFinalStepView() {
        XCTAssertEqual(
            OnboardingView.contentKind(for: .finalStep),
            .finalStep
        )
    }

    @MainActor
    func testOnboardingViewSourceKeepsMacDifferencesLimitedToTerminationDismissHandling() throws {
        let normalized = try onboardingViewSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("#ifos(macOS)"))
        XCTAssertTrue(normalized.contains("allowsTerminationDismiss"))
    }

    @MainActor
    func testOnboardingChromeLayoutSourceDoesNotContainMacSpecificLayoutBranch() throws {
        let normalized = try onboardingChromeLayoutSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("#ifos(macOS)"))
        XCTAssertTrue(normalized.contains("return.regular"))
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
    private func makeTestingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        )
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

    @MainActor
    private func mountOnboardingView(
        viewModel: OnboardingViewModel,
        interfaceStyle: UIUserInterfaceStyle = .light,
        width: CGFloat = 390,
        height: CGFloat = 844
    ) -> UIHostingController<AnyView> {
        let controller = UIHostingController(
            rootView: AnyView(
                OnboardingView(viewModel: viewModel)
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

    private func findLabels(in view: UIView) -> [UILabel] {
        var labels = view.subviews.compactMap { $0 as? UILabel }
        for subview in view.subviews {
            labels.append(contentsOf: findLabels(in: subview))
        }
        return labels
    }

    private func onboardingViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("OnboardingView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read OnboardingView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func onboardingChromeLayoutSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("OnboardingChromeLayout.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read OnboardingChromeLayout.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func onboardingBottomAreaViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("OnboardingBottomAreaView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read OnboardingBottomAreaView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func verifyEmailStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("VerifyEmailStepView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read VerifyEmailStepView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func chooseProviderStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("ChooseProviderStepView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read ChooseProviderStepView.swift: \(error)", file: file, line: line)
            throw error
        }
    }

    private func notificationsPermissionStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent("NotificationsPermissionStepView.swift")

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read NotificationsPermissionStepView.swift: \(error)", file: file, line: line)
            throw error
        }
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
