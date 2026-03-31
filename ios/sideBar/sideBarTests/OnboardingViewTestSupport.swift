#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

class OnboardingViewTestCase: XCTestCase {
    func makeUserDefaults() -> UserDefaults {
        let suiteName = "OnboardingViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    func makeTestingViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            authSession: MockAuthSessionForOnboarding(),
            onboardingAPI: MockOnboardingAPI(),
            settingsAPI: OnboardingMockSettingsAPI(),
            isTestingOnboarding: true,
            userDefaults: makeUserDefaults()
        )
    }

    @MainActor
    func mountCreateAccountStep(
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
    func mountOnboardingView(
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

    func findTextFields(in view: UIView) -> [UITextField] {
        var textFields = view.subviews.compactMap { $0 as? UITextField }
        for subview in view.subviews {
            textFields.append(contentsOf: findTextFields(in: subview))
        }
        return textFields
    }

    func onboardingViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "OnboardingView.swift",
            file: file,
            line: line
        )
    }

    func onboardingChromeLayoutSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "OnboardingChromeLayout.swift",
            file: file,
            line: line
        )
    }

    func onboardingBottomAreaViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "OnboardingBottomAreaView.swift",
            file: file,
            line: line
        )
    }

    func verifyEmailStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "VerifyEmailStepView.swift",
            file: file,
            line: line
        )
    }

    func chooseProviderStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "ChooseProviderStepView.swift",
            file: file,
            line: line
        )
    }

    func createAccountStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "CreateAccountStepView.swift",
            file: file,
            line: line
        )
    }

    func notificationsPermissionStepViewSource(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        try sourceFile(
            named: "NotificationsPermissionStepView.swift",
            file: file,
            line: line
        )
    }

    func rgbaComponents(for color: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue, alpha]
    }

    private func sourceFile(
        named fileName: String,
        file: StaticString,
        line: UInt
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Onboarding")
            .appendingPathComponent(fileName)

        do {
            return try String(contentsOf: sourceURL, encoding: .utf8)
        } catch {
            XCTFail("Failed to read \(fileName): \(error)", file: file, line: line)
            throw error
        }
    }
}
#endif
