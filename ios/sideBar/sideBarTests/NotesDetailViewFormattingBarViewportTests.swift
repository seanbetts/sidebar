#if os(iOS)
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
        let nativeViewModel = NativeNoteEditorViewModel()
        nativeViewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let textView = try mountTextView(
            viewModel: nativeViewModel,
            makeKeyAndVisible: true,
            formattingBarPresentation: .floatingTopTrailing,
            maxContentWidth: 640,
            width: 500,
            height: 900
        )
        let window = try XCTUnwrap(textView.window)
        let bar = UIKitNoteFormattingBar(
            configuration: makeFormattingViewportConfiguration(for: nativeViewModel),
            presentation: .floatingTopTrailing
        )
        bar.frame = CGRect(x: 420, y: 16, width: 60, height: 48)
        window.addSubview(bar)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location
        let targetRange = NSRange(location: targetOffset, length: 0)

        textView.selectedRange = targetRange
        textView.delegate?.textViewDidChangeSelection?(textView)
        XCTAssertTrue(textView.becomeFirstResponder())
        textView.layoutIfNeeded()
        textView.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        drainNotesHostingRunLoop()
        let baselineOffset = textView.contentOffset.y

        bar.presentPopover()
        drainNotesHostingRunLoop()
        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)

        let popoverRoot: UIView = try XCTUnwrap(findFormattingPopoverRoot(startingAt: window))
        let subheadingButton: UIButton = try XCTUnwrap(
            findDescendantButton(in: popoverRoot, accessibilityIdentifier: "note-formatting-text-style-subheading")
        )
        subheadingButton.sendActions(for: UIControl.Event.touchUpInside)
        drainNotesHostingRunLoop()

        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)
    }
}

@MainActor
@available(iOS 26.0, *)
private func makeFormattingViewportConfiguration(
    for viewModel: NativeNoteEditorViewModel
) -> NoteFormattingBarConfiguration {
    NoteFormattingBarConfiguration(
        activeTextStyle: .body,
        isTextStyleSectionEnabled: true,
        isBodyTextStyleEnabled: true,
        isTitleTextStyleEnabled: true,
        isHeadingTextStyleEnabled: true,
        isSubheadingTextStyleEnabled: true,
        isBoldActive: false,
        isItalicActive: false,
        isUnderlineActive: false,
        isStrikethroughActive: false,
        isEnabled: true,
        onTextStyleSelection: { style in
            viewModel.setTextStyle(style)
        },
        onBoldTap: {
            viewModel.setFormatting(.bold, enabled: !viewModel.isFormattingActive(.bold))
        },
        onItalicTap: {
            viewModel.setFormatting(.italic, enabled: !viewModel.isFormattingActive(.italic))
        },
        onUnderlineTap: {
            viewModel.setFormatting(.underline, enabled: !viewModel.isFormattingActive(.underline))
        },
        onStrikethroughTap: {
            viewModel.setFormatting(.strikethrough, enabled: !viewModel.isFormattingActive(.strikethrough))
        }
    )
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
