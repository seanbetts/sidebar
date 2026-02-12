import UIKit
import XCTest
@testable import ShareExtension

final class ShareSuccessViewTests: XCTestCase {
    func testSuccessViewUsesInvertedSuccessIconColorsByAppearance() {
        let message = "Website saved."
        let subject = ShareSuccessView(message: message)

        guard let iconView = subject.firstSubview(where: {
            ($0 as? UIImageView)?.accessibilityIdentifier == "share-success-icon"
        }) as? UIImageView else {
            XCTFail("Expected success icon in view hierarchy.")
            return
        }

        guard let iconBackgroundColor = iconView.superview?.backgroundColor else {
            XCTFail("Expected success icon background view.")
            return
        }

        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertTrue(colorsEqual(iconView.tintColor, .white, traitCollection: lightTraits))
        XCTAssertTrue(colorsEqual(iconBackgroundColor, .black, traitCollection: lightTraits))

        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertTrue(colorsEqual(iconView.tintColor, .black, traitCollection: darkTraits))
        XCTAssertTrue(colorsEqual(iconBackgroundColor, .white, traitCollection: darkTraits))

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

        let hasAdaptiveLogo = UIImage(named: "logo-light", in: Bundle.main, compatibleWith: nil) != nil
            || UIImage(named: "logo-dark", in: Bundle.main, compatibleWith: nil) != nil
        let hasBundledLogo = hasAdaptiveLogo || UIImage(named: "AppLogo", in: Bundle.main, compatibleWith: nil) != nil
        XCTAssertEqual(!logoView.isHidden, hasBundledLogo)
    }

    func testSuccessViewUsesMinimalBrandStackAndNoCardContainer() {
        let subject = ShareSuccessView(message: "Saved")

        let cardContainer = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-state-card"
        })
        XCTAssertNil(cardContainer)

        guard let brandStack = subject.firstSubview(where: {
            ($0 as? UIStackView)?.accessibilityIdentifier == "share-brand-stack"
        }) as? UIStackView else {
            XCTFail("Expected brand stack in view hierarchy.")
            return
        }

        XCTAssertEqual(brandStack.axis, .vertical)
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
