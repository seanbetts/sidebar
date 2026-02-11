import UIKit
import XCTest
@testable import ShareExtension

final class ShareSuccessViewTests: XCTestCase {
    func testSuccessViewUsesGreenSuccessIconAndMessageText() {
        let message = "Website saved."
        let subject = ShareSuccessView(message: message)

        guard let iconView = subject.firstSubview(where: {
            ($0 as? UIImageView)?.accessibilityIdentifier == "share-success-icon"
        }) as? UIImageView else {
            XCTFail("Expected success icon in view hierarchy.")
            return
        }

        XCTAssertTrue(colorsEqual(iconView.tintColor, .systemGreen))

        let labels = subject.allSubviews(of: UILabel.self)
        XCTAssertTrue(labels.contains(where: { $0.text == "sideBar" }))
        XCTAssertTrue(labels.contains(where: { $0.text == message }))
    }

    func testBrandLogoVisibilityReflectsAssetAvailability() {
        let subject = ShareSuccessView(message: "Saved")

        guard let logoView = subject.firstSubview(where: {
            ($0 as? UIImageView)?.accessibilityIdentifier == "share-brand-logo"
        }) as? UIImageView else {
            XCTFail("Expected brand logo image view in hierarchy.")
            return
        }

        let hasBundledLogo = UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: nil) != nil
        XCTAssertEqual(!logoView.isHidden, hasBundledLogo)
    }

    private func colorsEqual(
        _ left: UIColor,
        _ right: UIColor,
        traitCollection: UITraitCollection = UITraitCollection(userInterfaceStyle: .light)
    ) -> Bool {
        left.resolvedColor(with: traitCollection).isEqual(right.resolvedColor(with: traitCollection))
    }
}

private extension UIView {
    func firstSubview(where predicate: (UIView) -> Bool) -> UIView? {
        if predicate(self) {
            return self
        }
        for child in subviews {
            if let match = child.firstSubview(where: predicate) {
                return match
            }
        }
        return nil
    }

    func allSubviews<T: UIView>(of type: T.Type) -> [T] {
        var result: [T] = []
        if let typed = self as? T {
            result.append(typed)
        }
        for child in subviews {
            result.append(contentsOf: child.allSubviews(of: type))
        }
        return result
    }
}
