#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitPDFControlBarTests: XCTestCase {
    func testBarReportsCompactIntrinsicSize() {
        let bar = UIKitPDFControlBar(configuration: .disabled)
        let size = bar.intrinsicContentSize

        XCTAssertNotEqual(size.width, UIView.noIntrinsicMetric)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertLessThan(size.width, 120)
        XCTAssertEqual(size.height, PDFControlBarChrome.entryControlHeight)
    }

    func testBarUsesIntrinsicHeightWithoutSelfOwnedFixedHeightConstraint() {
        let bar = UIKitPDFControlBar(configuration: .disabled)

        XCTAssertFalse(
            bar.constraints.contains(where: { constraint in
                constraint.firstItem === bar
                    && constraint.secondItem == nil
                    && constraint.firstAttribute == .height
                    && constraint.relation == .equal
            })
        )
    }
}
#endif
