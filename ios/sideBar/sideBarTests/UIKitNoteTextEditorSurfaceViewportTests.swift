#if os(iOS)
import SwiftUI
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

    func testMountedSurfaceUsesKeyboardLayoutContainer() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarPresentation: .floatingTopTrailing,
            height: 320
        )

        XCTAssertTrue(textView.superview is UIKitNoteTextEditorContainerView)
    }

    func testKeyboardNotificationDoesNotChangeViewportInsetsWhenLayoutOwnsKeyboardSpace() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(
                Array(repeating: "Visible line", count: 40).joined(separator: "\n")
            ),
            plainText: Array(repeating: "Visible line", count: 40).joined(separator: "\n")
        )
        let trackingTextView = try XCTUnwrap(
            mountTextView(
                viewModel: viewModel,
                formattingBarPresentation: .floatingTopTrailing,
                makeTextView: { UIKitNoteTextEditorSurface.AccessoryTextView() },
                height: 320
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        let baselineContentInset = trackingTextView.contentInset
        let baselineIndicatorInsets = trackingTextView.verticalScrollIndicatorInsets
        let keyboardFrameInView = CGRect(
            x: 0,
            y: 280,
            width: trackingTextView.bounds.width,
            height: 40
        )
        let keyboardFrameInWindow = trackingTextView.convert(
            keyboardFrameInView,
            to: trackingTextView.window
        )
        let keyboardFrameInScreen = trackingTextView.window?.convert(
            keyboardFrameInWindow,
            to: nil
        ) ?? keyboardFrameInWindow

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: keyboardFrameInScreen)
            ]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(trackingTextView.contentInset, baselineContentInset)
        XCTAssertEqual(
            trackingTextView.verticalScrollIndicatorInsets,
            baselineIndicatorInsets
        )
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
