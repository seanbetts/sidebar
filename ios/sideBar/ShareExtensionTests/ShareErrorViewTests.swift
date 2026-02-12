import UIKit
import XCTest
@testable import ShareExtension

final class ShareErrorViewTests: XCTestCase {
    func testErrorViewDoesNotRenderAnyActionButtons() {
        let subject = ShareErrorView(message: "Failed")
        let buttons = subject.allSubviews(of: UIButton.self)
        XCTAssertTrue(buttons.isEmpty)
    }

    func testErrorViewUsesVerticalBrandStack() {
        let subject = ShareErrorView(message: "Failed")

        guard let brandStack = subject.firstSubview(where: {
            ($0 as? UIStackView)?.accessibilityIdentifier == "share-brand-stack"
        }) as? UIStackView else {
            XCTFail("Expected brand stack in view hierarchy.")
            return
        }

        XCTAssertEqual(brandStack.axis, .vertical)
    }

    func testErrorViewShowsGrabHandle() {
        let subject = ShareErrorView(message: "Failed")
        let grabHandle = subject.firstSubview(where: {
            $0.accessibilityIdentifier == "share-grab-handle"
        })
        XCTAssertNotNil(grabHandle)
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
