#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension NotesFormattingViewportTests {
    func testVisibleTapSelectionDoesNotArmViewportRepairLoop() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let entryOffset = NSString(string: plainText).range(of: "Line 60 body text").location
        let tapOffset = NSString(string: plainText).range(of: "Line 58 body text").location

        context.editorViewModel.enterEditMode(at: .characterOffset(entryOffset))
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findInteractionOwnershipTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        XCTAssertTrue(editorTextView.becomeFirstResponder())
        drainNotesHostingRunLoop()
        let baselineContentOffset = editorTextView.contentOffset

        simulateUIKitTouchSelectionChange(
            on: editorTextView,
            to: NSRange(location: tapOffset, length: 0)
        )
        await waitUntil {
            editorTextView.selectedRange.location == tapOffset
        }
        let settledContentOffset = editorTextView.contentOffset
        let settledSelectionRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        let maximumNativeTapNudge = max((editorTextView.font?.lineHeight ?? 0) * 3, 48)

        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        XCTAssertLessThan(
            abs(settledContentOffset.y - baselineContentOffset.y),
            maximumNativeTapNudge,
            "Visible tap selection should not trigger a large viewport jump"
        )
        XCTAssertTrue(
            editorTextView.visibleViewportRect().intersects(settledSelectionRect.insetBy(dx: 0, dy: -1)),
            "Visible tap selection should leave the native caret visible"
        )
        XCTAssertEqual(
            editorTextView.contentOffset.y,
            settledContentOffset.y,
            accuracy: 0.5,
            "Visible tap selection should not trigger deferred viewport repair after UIKit settles"
        )
    }

    func testVisibleArrowKeySelectionDoesNotArmViewportRepairLoop() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let entryOffset = NSString(string: plainText).range(of: "Line 70 body text").location
        let previousLineOffset = NSString(string: plainText).range(of: "Line 69 body text").location

        context.editorViewModel.enterEditMode(at: .characterOffset(entryOffset))
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findInteractionOwnershipTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        XCTAssertTrue(editorTextView.becomeFirstResponder())
        drainNotesHostingRunLoop()
        editorTextView.layoutIfNeeded()
        let baselineRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        let targetViewportOffset = CGPoint(
            x: 0,
            y: max(
                baselineRect.maxY - editorTextView.visibleViewportRect().height,
                -editorTextView.adjustedContentInset.top
            )
        )
        editorTextView.setContentOffset(
            UIKitNoteTextEditorSurface.clampedContentOffset(targetViewportOffset, for: editorTextView),
            animated: false
        )
        drainNotesHostingRunLoop()
        let baselineContentOffset = editorTextView.contentOffset

        editorTextView.selectedRange = NSRange(location: previousLineOffset, length: 0)
        await waitUntil {
            editorTextView.selectedRange.location == previousLineOffset
        }

        XCTAssertEqual(
            editorTextView.contentOffset.y,
            baselineContentOffset.y,
            accuracy: 0.5,
            "Visible arrow-key selection should leave viewport ownership with UIKit"
        )
    }
}

@MainActor
private func findInteractionOwnershipTextView(
    in view: UIView?,
    accessibilityIdentifier: String
) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }

    for subview in view.subviews {
        if let match = findInteractionOwnershipTextView(
            in: subview,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            return match
        }
    }

    return nil
}
#endif
