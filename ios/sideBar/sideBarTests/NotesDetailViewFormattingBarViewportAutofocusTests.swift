#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension NotesFormattingViewportTests {
    func testUIKitSurfaceAutofocusMountDoesNotCarryPendingViewportOffset() throws {
        let plainText = (0..<40)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location
        viewModel.selection = viewModel.insertionPointSelection(
            forUTF16Offset: targetOffset,
            in: viewModel.attributedContent
        )
        let trackingTextView = ViewportTrackingAccessoryTextView()

        let textView = try mountTextView(
            viewModel: viewModel,
            autofocusEnabled: true,
            attachToWindow: true,
            makeKeyAndVisible: true,
            formattingBarPresentation: .floatingTopTrailing,
            makeTextView: { trackingTextView },
            width: 900,
            height: 700
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertNil(
            trackingTextView.debugPendingInitialViewportOffset,
            "Autofocus mount should not arm pending viewport restoration"
        )
    }
}
#endif
