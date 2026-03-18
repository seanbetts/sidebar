#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurfaceTests {
    func testUIKitSurfaceUsesReadModeTextPaddingInsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset.left, NoteTextLayout.horizontalPadding)
        XCTAssertEqual(textView.textContainerInset.right, NoteTextLayout.horizontalPadding)
        XCTAssertEqual(textView.textContainerInset.top, NoteTextLayout.verticalPadding)
        XCTAssertEqual(textView.textContainerInset.bottom, NoteTextLayout.verticalPadding)
    }

    func testKeyboardViewportInsetAddsKeyboardOverlapAndAccessoryHeight() {
        let bottomInset = UIKitNoteTextEditorSurface.resolvedBottomViewportInset(
            textViewBounds: CGRect(x: 0, y: 0, width: 360, height: 640),
            keyboardFrameInView: CGRect(x: 0, y: 420, width: 360, height: 220),
            accessoryHeight: 56
        )

        XCTAssertEqual(bottomInset, 276, accuracy: 0.5)
    }

    func testKeyboardViewportInsetIgnoresNonIntersectingKeyboardFrames() {
        let bottomInset = UIKitNoteTextEditorSurface.resolvedBottomViewportInset(
            textViewBounds: CGRect(x: 0, y: 0, width: 360, height: 640),
            keyboardFrameInView: CGRect(x: 0, y: 700, width: 360, height: 220),
            accessoryHeight: 56
        )

        XCTAssertEqual(bottomInset, 0, accuracy: 0.5)
    }

    func testViewportInsetChangeDoesNotScrollWhenSelectionAlreadyVisible() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(
                Array(repeating: "Visible line", count: 40).joined(separator: "\n")
            ),
            plainText: Array(repeating: "Visible line", count: 40).joined(separator: "\n")
        )
        let topInsertion = viewModel.attributedContent.startIndex
        viewModel.selection = AttributedTextSelection(range: topInsertion..<topInsertion)
        let trackingTextView = ScrollTrackingAccessoryTextView()
        let textView = try XCTUnwrap(
            mountTextView(
                viewModel: viewModel,
                formattingBarPresentation: .floatingTopTrailing,
                makeTextView: { trackingTextView },
                height: 320
            ) as? ScrollTrackingAccessoryTextView
        )
        let baselineScrollCallCount = textView.scrollRangeToVisibleCallCount
        let keyboardFrameInView = CGRect(x: 0, y: 280, width: textView.bounds.width, height: 40)
        let keyboardFrameInWindow = textView.convert(keyboardFrameInView, to: textView.window)
        let keyboardFrameInScreen = textView.window?.convert(keyboardFrameInWindow, to: nil) ?? keyboardFrameInWindow

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboardFrameInScreen)
            ]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(textView.scrollRangeToVisibleCallCount, baselineScrollCallCount)
    }

    func testWideIPadSurfaceKeepsTextViewFullWidthAndCentersReadableColumn() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarPresentation: .floatingTopTrailing,
            maxContentWidth: 360,
            width: 600,
            height: 320
        )

        XCTAssertEqual(textView.bounds.width, 600, accuracy: 0.5)
        XCTAssertEqual(
            textView.textContainerInset.left,
            NoteTextLayout.horizontalPadding + 120,
            accuracy: 0.5
        )
        XCTAssertEqual(
            textView.textContainerInset.right,
            NoteTextLayout.horizontalPadding + 120,
            accuracy: 0.5
        )
    }
}

#endif
