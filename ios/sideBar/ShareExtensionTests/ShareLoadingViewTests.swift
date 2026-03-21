import UIKit
import XCTest
@testable import ShareExtension
import sideBarShared

final class ShareLoadingViewTests: XCTestCase {
    func testLoadingViewUsesMinimalSheetBackground() {
        let subject = ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite))
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertTrue(colorsEqual(subject.hostBackgroundColor, .clear, traitCollection: lightTraits))
        XCTAssertTrue(colorsEqual(subject.hostBackgroundColor, .clear, traitCollection: darkTraits))
        XCTAssertTrue(colorsEqual(subject.backgroundColor ?? .clear, .clear, traitCollection: lightTraits))
        XCTAssertTrue(colorsEqual(subject.backgroundColor ?? .clear, .clear, traitCollection: darkTraits))
    }

    func testLoadingViewDoesNotRenderCardContainer() {
        let subject = ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite))

        let cardContainer = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-state-card"
        })
        XCTAssertNil(cardContainer)
    }

    func testLoadingViewOmitsBrandStack() {
        let subject = ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite))
        let brandStack = subject.firstSubview(where: {
            ($0 as? UIStackView)?.accessibilityIdentifier == "share-brand-stack"
        })
        XCTAssertNil(brandStack)
    }

    func testLoadingViewUsesQueueFirstCopy() {
        let subject = ShareLoadingView(message: ExtensionUserMessageCatalog.message(for: .savingWebsite))

        let label = subject.firstSubview(where: { $0 is UILabel }) as? UILabel

        XCTAssertEqual(label?.text, "Saving for later...")
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
