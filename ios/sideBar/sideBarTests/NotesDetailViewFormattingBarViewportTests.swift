#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesFormattingViewportTests: NotesDetailViewHostingTestCase {
    func testFloatingPopoverTextStyleTapKeepsViewportStable() async throws {
        let plainText = (0..<40)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        context.editorViewModel.enterEditMode()
        let environment = makeNotesDetailTestEnvironment()
        let view = NotesDetailView(
            viewModel: context.notesViewModel,
            editorViewModel: context.editorViewModel,
            isMoveSheetPresented: .constant(false),
            moveSelection: .constant(""),
            isDeleteAlertPresented: .constant(false),
            isExporting: .constant(false),
            exportDocument: .constant(nil),
            exportFilename: .constant(""),
            formattingBarPresentationOverride: .floatingTopTrailing
        )
        let controller = mount(view, environment: environment, makeKeyAndVisible: true)
        let rootView = try XCTUnwrap(controller.view)
        let textView = try XCTUnwrap(findDescendantTextView(in: rootView))
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location
        let targetRange = NSRange(location: targetOffset, length: 0)

        textView.selectedRange = targetRange
        textView.delegate?.textViewDidChangeSelection?(textView)
        XCTAssertTrue(textView.becomeFirstResponder())
        textView.layoutIfNeeded()
        textView.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let baselineOffset = textView.contentOffset.y

        let menuButton = try XCTUnwrap(
            findDescendantButton(in: rootView, accessibilityIdentifier: "note-formatting-menu")
        )
        menuButton.sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)

        let popoverRoot = try XCTUnwrap(
            findFormattingPopoverRoot(startingAt: controller.view.window)
        )
        let subheadingButton = try XCTUnwrap(
            findDescendantButton(
                in: popoverRoot,
                accessibilityIdentifier: "note-formatting-text-style-subheading"
            )
        )
        subheadingButton.sendActions(for: .touchUpInside)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)
    }
}

@MainActor
private func findDescendantTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }

    for subview in view.subviews {
        if let match = findDescendantTextView(in: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func findDescendantButton(in view: UIView, accessibilityIdentifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
        return button
    }

    for subview in view.subviews {
        if let match = findDescendantButton(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }

    return nil
}

@MainActor
private func findFormattingPopoverRoot(startingAt view: UIView?) -> UIView? {
    guard let view else { return nil }
    if view.accessibilityIdentifier == "note-formatting-popover" {
        return view
    }

    for subview in view.subviews {
        if let match = findFormattingPopoverRoot(startingAt: subview) {
            return match
        }
    }

    return nil
}
#endif
