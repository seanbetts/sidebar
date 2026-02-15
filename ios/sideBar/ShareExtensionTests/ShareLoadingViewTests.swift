import UIKit
import XCTest
@testable import ShareExtension

final class ShareLoadingViewTests: XCTestCase {
    func testLoadingViewUsesSystemBackgroundForCardSheet() {
        let subject = ShareLoadingView(message: "Saving website...")
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertTrue(colorsEqual(subject.hostBackgroundColor, .systemBackground, traitCollection: lightTraits))
        XCTAssertTrue(colorsEqual(subject.hostBackgroundColor, .systemBackground, traitCollection: darkTraits))
        XCTAssertTrue(colorsEqual(subject.backgroundColor ?? .clear, .systemBackground, traitCollection: lightTraits))
        XCTAssertTrue(colorsEqual(subject.backgroundColor ?? .clear, .systemBackground, traitCollection: darkTraits))
    }

    func testLoadingViewUsesSecondarySystemBackgroundForCardContainer() {
        let subject = ShareLoadingView(message: "Saving website...")
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        guard let cardContainer = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-state-card"
        }) else {
            XCTFail("Expected card container in view hierarchy.")
            return
        }

        XCTAssertTrue(
            colorsEqual(cardContainer.backgroundColor ?? .clear, .secondarySystemBackground, traitCollection: lightTraits)
        )
        XCTAssertTrue(
            colorsEqual(cardContainer.backgroundColor ?? .clear, .secondarySystemBackground, traitCollection: darkTraits)
        )
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
}
