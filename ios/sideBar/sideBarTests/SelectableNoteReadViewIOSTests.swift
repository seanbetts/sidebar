#if os(iOS)
import XCTest
import UIKit
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadViewTests {
    func testCharacterOffsetForEditingActivationKeepsReadTextViewOnTextKit2() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try lineEndOverflowClickPoint(in: textView, characterIndex: 2)

        XCTAssertNotNil(textView.textLayoutManager)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, 3)
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testCharacterOffsetForEditingActivationClampsTapBelowContentToEndOfNoteOnIOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try belowContentClickPoint(in: textView, characterIndex: 6)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, textView.text.utf16.count)
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testReadSurfaceUsesBaseReadableTextViewPaddingOnIOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )

        XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset.top, NoteTextLayout.verticalPadding, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.left, NoteTextLayout.horizontalPadding, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.bottom, NoteTextLayout.verticalPadding, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.right, NoteTextLayout.horizontalPadding, accuracy: 0.001)
    }

    func testMakePlatformAttributedContentUsesDynamicLabelColorOnIOS() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "Hello")
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let color = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            color.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
    }
}
#endif
