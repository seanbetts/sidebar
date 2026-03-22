#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class SelectableNoteReadViewMountedIOSTests: XCTestCase {
    func testWideMountedReadSurfaceKeepsTextViewFullWidthAndCentersReadableColumn() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 900, height: 240),
            maxContentWidth: 640
        )
        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((900 - 640) / 2)

        XCTAssertEqual(textView.bounds.width, 900, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.left, expectedHorizontalInset, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.right, expectedHorizontalInset, accuracy: 0.5)
    }
}
#endif
