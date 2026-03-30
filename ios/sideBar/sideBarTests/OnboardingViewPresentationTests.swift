#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

final class OnboardingViewPresentationTests: OnboardingViewTestCase {
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
}
#endif
