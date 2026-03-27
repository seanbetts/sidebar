#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesReadModeViewportRestorationTests: NotesDetailViewHostingTestCase {
    private struct ViewportExpectation {
        let expectedReadContentOffsetY: CGFloat
        let expectedViewportAnchorY: CGFloat
        let editorTargetRect: CGRect
    }

    func testEditToReadTransitionFromMiddleKeepsTargetLineAtSameRelativePosition() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location
        context.editorViewModel.enterEditMode()
        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        let expectation = try await moveEditorViewportToTargetLine(
            editorTextView,
            context: context,
            targetOffset: targetOffset
        )

        environment.shortcutActionEvent = ShortcutActionEvent(
            action: .closeItem,
            section: .notes,
            pane: nil
        )

        await waitUntil {
            context.editorViewModel.presentationMode == .read &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let readTextViewDuringExitHold = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let readContentOffsetDuringExitHold = readTextViewDuringExitHold.contentOffset

        await waitUntil {
            abs(
                readTextViewDuringExitHold.contentOffset.y - expectation.expectedReadContentOffsetY
            ) <= 2 &&
                context.editorViewModel.pendingReadSurfaceViewportOffset == nil
        }

        let restoredReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        let restoration = context.editorViewModel.debugLastExitReadViewportRestoration
        let pendingReadSurfaceViewportOffset = context.editorViewModel.pendingReadSurfaceViewportOffset
        let pendingReadSurfaceViewportAnchorTarget =
            context.editorViewModel.pendingReadSurfaceViewportAnchorTarget
        let pendingReadSurfaceViewportAnchorY = context.editorViewModel.pendingReadSurfaceViewportAnchorY

        XCTAssertEqual(
            restoredReadTextView.contentOffset.y,
            expectation.expectedReadContentOffsetY,
            accuracy: 2,
            failureMessage(
                expectedReadContentOffsetY: expectation.expectedReadContentOffsetY,
                editorTextView: editorTextView,
                readContentOffsetDuringExitHold: readContentOffsetDuringExitHold,
                readTextViewDuringExitHold: readTextViewDuringExitHold,
                restoredReadTextView: restoredReadTextView,
                restoration: restoration,
                pendingReadSurfaceViewportOffset: pendingReadSurfaceViewportOffset,
                pendingReadSurfaceViewportAnchorTarget: pendingReadSurfaceViewportAnchorTarget,
                pendingReadSurfaceViewportAnchorY: pendingReadSurfaceViewportAnchorY,
                editorTargetRect: expectation.editorTargetRect,
                expectedViewportAnchorY: expectation.expectedViewportAnchorY
            )
        )
    }

    private func moveEditorViewportToTargetLine(
        _ editorTextView: UIKitNoteTextEditorSurface.AccessoryTextView,
        context: NotesDetailViewTestContext,
        targetOffset: Int
    ) async throws -> ViewportExpectation {
        XCTAssertTrue(
            context.editorViewModel.nativeEditorTextView === editorTextView,
            "Expected attached editor text view to match mounted editor text view"
        )
        context.editorViewModel.attachedNativeEditorViewModel?.setInsertionPoint(
            characterOffset: targetOffset
        )
        drainNotesHostingRunLoop()

        let editorTargetPosition = try XCTUnwrap(
            editorTextView.position(from: editorTextView.beginningOfDocument, offset: targetOffset)
        )
        let initialEditorTargetRect = editorTextView.caretRect(for: editorTargetPosition)
        let editorViewportHeight = editorTextView.bounds.inset(by: editorTextView.adjustedContentInset).height
        let targetEditorOffset = CGPoint(
            x: 0,
            y: max(
                initialEditorTargetRect.midY - (editorViewportHeight * 0.55),
                -editorTextView.adjustedContentInset.top
            )
        )
        editorTextView.setContentOffset(targetEditorOffset, animated: false)
        drainNotesHostingRunLoop()
        await waitUntil {
            abs(editorTextView.contentOffset.y - targetEditorOffset.y) <= 1
        }

        let editorTargetRect = editorTextView.caretRect(for: editorTargetPosition)
        let editorViewport = editorTextView.bounds.inset(by: editorTextView.adjustedContentInset)
        return ViewportExpectation(
            expectedReadContentOffsetY: editorTextView.contentOffset.y,
            expectedViewportAnchorY: editorTargetRect.midY - editorViewport.minY,
            editorTargetRect: editorTargetRect
        )
    }

    private func failureMessage(
        expectedReadContentOffsetY: CGFloat,
        editorTextView: UIKitNoteTextEditorSurface.AccessoryTextView,
        readContentOffsetDuringExitHold: CGPoint,
        readTextViewDuringExitHold: UITextView,
        restoredReadTextView: UITextView,
        restoration: NotesEditorViewModel.PendingReadViewportRestoration?,
        pendingReadSurfaceViewportOffset: CGPoint?,
        pendingReadSurfaceViewportAnchorTarget: NotesEditorViewModel.PendingEditSelectionTarget?,
        pendingReadSurfaceViewportAnchorY: CGFloat?,
        editorTargetRect: CGRect,
        expectedViewportAnchorY: CGFloat
    ) -> String {
        "expectedReadContentOffsetY=\(expectedReadContentOffsetY) "
            + "editorContentOffsetAtAssertion=\(editorTextView.contentOffset) "
            + "readContentOffsetDuringExitHold=\(readContentOffsetDuringExitHold) "
            + "sameReadTextViewAcrossExit=\(readTextViewDuringExitHold === restoredReadTextView) "
            + "restoredReadContentOffset=\(restoredReadTextView.contentOffset) "
            + "exitRestorationOffset=\(String(describing: restoration?.offset)) "
            + "exitRestorationTarget=\(String(describing: restoration?.target)) "
            + "exitRestorationAnchorY=\(String(describing: restoration?.viewportAnchorY)) "
            + "pendingReadSurfaceViewportOffset=\(String(describing: pendingReadSurfaceViewportOffset)) "
            + "pendingReadSurfaceViewportAnchorTarget=\(String(describing: pendingReadSurfaceViewportAnchorTarget)) "
            + "pendingReadSurfaceViewportAnchorY=\(String(describing: pendingReadSurfaceViewportAnchorY)) "
            + "editorTargetRect=\(editorTargetRect) "
            + "expectedViewportAnchorY=\(expectedViewportAnchorY)"
    }
}

@MainActor
private func findTextView(in view: UIView?, accessibilityIdentifier: String) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }
    for subview in view.subviews {
        if let match = findTextView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }
    return nil
}
#endif
