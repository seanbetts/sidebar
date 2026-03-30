#if canImport(UIKit)
import sideBarShared
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

final class LoginViewPresentationTests: XCTestCase {
    private var retainedEnvironments: [AppEnvironment] = []

    @MainActor
    func testLoginPasswordFieldUsesSecurePasswordConfiguration() throws {
        let environment = makeEnvironment()
        let controller = mountLoginView(environment: environment)
        let secureField = try XCTUnwrap(
            findTextFields(in: controller.view).first(where: \.isSecureTextEntry)
        )
        XCTAssertTrue(secureField.becomeFirstResponder())

        XCTAssertTrue(secureField.isSecureTextEntry)
        XCTAssertEqual(secureField.textContentType, .password)
    }

    @MainActor
    private func mountLoginView(environment: AppEnvironment) -> UIHostingController<AnyView> {
        let controller = UIHostingController(
            rootView: AnyView(
                LoginView()
                    .environmentObject(environment)
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: frame)
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

    @MainActor
    private func makeEnvironment() -> AppEnvironment {
        let container = ServiceContainer(
            config: .fallbackForTesting(),
            authSession: PlaceholderAuthSession(authState: .signedOut),
            cacheClient: InMemoryCacheClient()
        )
        let environment = AppEnvironment(container: container)
        retainedEnvironments.append(environment)
        return environment
    }
}
#endif
