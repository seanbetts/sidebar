#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesReadModeViewportRestorationTests: NotesDetailViewHostingTestCase {
    private struct ViewportExpectation {
        let expectedViewportAnchorY: CGFloat
        let editorTargetRect: CGRect
        let targetOffset: Int
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
            self.actualViewportAnchorY(
                in: readTextViewDuringExitHold,
                targetOffset: expectation.targetOffset
            ).map {
                abs($0 - expectation.expectedViewportAnchorY) <= 2
            } == true &&
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
        let restoredReadViewportAnchorY = actualViewportAnchorY(
            in: restoredReadTextView,
            targetOffset: expectation.targetOffset
        )

        XCTAssertEqual(
            try XCTUnwrap(restoredReadViewportAnchorY),
            expectation.expectedViewportAnchorY,
            accuracy: 2,
            failureMessage(
                editorTextView: editorTextView,
                readContentOffsetDuringExitHold: readContentOffsetDuringExitHold,
                readTextViewDuringExitHold: readTextViewDuringExitHold,
                restoredReadTextView: restoredReadTextView,
                restoration: restoration,
                pendingReadSurfaceViewportOffset: pendingReadSurfaceViewportOffset,
                pendingReadSurfaceViewportAnchorTarget: pendingReadSurfaceViewportAnchorTarget,
                pendingReadSurfaceViewportAnchorY: pendingReadSurfaceViewportAnchorY,
                editorTargetRect: expectation.editorTargetRect,
                expectedViewportAnchorY: expectation.expectedViewportAnchorY,
                restoredReadViewportAnchorY: restoredReadViewportAnchorY
            )
        )
    }

    func testSingleCloseShortcutReturnsMountedDetailFromEditToRead() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)

        context.editorViewModel.enterEditMode()
        await waitUntil {
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }

        environment.shortcutActionEvent = ShortcutActionEvent(
            action: .closeItem,
            section: .notes,
            pane: nil
        )

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.presentationMode == .read
                && findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertNotNil(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        await waitUntil(timeout: .seconds(2)) {
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) == nil
        }
        XCTAssertNil(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            )
        )

        environment.shortcutActionEvent = ShortcutActionEvent(
            action: .closeItem,
            section: .notes,
            pane: nil
        )

        await waitUntil(timeout: .seconds(2)) {
            context.notesViewModel.activeNote == nil
        }
        XCTAssertNil(context.notesViewModel.activeNote)
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
            expectedViewportAnchorY: editorTargetRect.midY - editorViewport.minY,
            editorTargetRect: editorTargetRect,
            targetOffset: targetOffset
        )
    }

    private func actualViewportAnchorY(in textView: UITextView, targetOffset: Int) -> CGFloat? {
        SelectableNoteReadView.viewportAnchorYForEditingActivation(
            in: textView,
            target: .characterOffset(targetOffset)
        )
    }

    private func failureMessage(
        editorTextView: UIKitNoteTextEditorSurface.AccessoryTextView,
        readContentOffsetDuringExitHold: CGPoint,
        readTextViewDuringExitHold: UITextView,
        restoredReadTextView: UITextView,
        restoration: NotesEditorViewModel.PendingReadViewportRestoration?,
        pendingReadSurfaceViewportOffset: CGPoint?,
        pendingReadSurfaceViewportAnchorTarget: NotesEditorViewModel.PendingEditSelectionTarget?,
        pendingReadSurfaceViewportAnchorY: CGFloat?,
        editorTargetRect: CGRect,
        expectedViewportAnchorY: CGFloat,
        restoredReadViewportAnchorY: CGFloat?
    ) -> String {
        "editorContentOffsetAtAssertion=\(editorTextView.contentOffset) "
            + "readContentOffsetDuringExitHold=\(readContentOffsetDuringExitHold) "
            + "sameReadTextViewAcrossExit=\(readTextViewDuringExitHold === restoredReadTextView) "
            + "restoredReadContentOffset=\(restoredReadTextView.contentOffset) "
            + "restoredReadViewportAnchorY=\(String(describing: restoredReadViewportAnchorY)) "
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
