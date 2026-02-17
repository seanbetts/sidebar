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
        XCTAssertTrue(labels.contains(where: { $0.text == message }))
    }

    func testSuccessViewOmitsBrandLogo() {
        let subject = ShareSuccessView(message: "Saved")

        let logoView = subject.firstSubview(where: {
            ($0 as? UIImageView)?.accessibilityIdentifier == "share-brand-logo"
        })
        XCTAssertNil(logoView)
    }

    func testSuccessViewUsesMinimalLayoutWithoutBrandStackOrCardContainer() {
        let subject = ShareSuccessView(message: "Saved")
        XCTAssertTrue(colorsEqual(subject.backgroundColor ?? .clear, .clear))
        XCTAssertTrue(colorsEqual(subject.hostBackgroundColor, .clear))

        let cardContainer = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-state-card"
        })
        XCTAssertNil(cardContainer)

        let brandStack = subject.firstSubview(where: {
            ($0 as? UIStackView)?.accessibilityIdentifier == "share-brand-stack"
        })
        XCTAssertNil(brandStack)
    }

    func testSuccessViewShowsGrabHandle() {
        let subject = ShareSuccessView(message: "Saved")
        let grabHandle = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-grab-handle"
        })
        XCTAssertNotNil(grabHandle)
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
