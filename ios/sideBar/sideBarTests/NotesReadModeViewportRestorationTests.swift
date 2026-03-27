#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesReadModeViewportRestorationTests: NotesDetailViewHostingTestCase {
    func testEditToReadTransitionFromMiddleRestoresReadViewportOffset() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
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
        let targetEditorOffset = CGPoint(x: 0, y: 420)
        editorTextView.setContentOffset(targetEditorOffset, animated: false)
        drainNotesHostingRunLoop()
        await waitUntil {
            abs(editorTextView.contentOffset.y - targetEditorOffset.y) <= 1
        }

        context.makeView().handleCloseShortcut(
            editedDocument: context.editorViewModel.currentSemanticDocumentSnapshot()
        )

        await waitUntil {
            context.editorViewModel.presentationMode == .read &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let restoredReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        XCTAssertEqual(restoredReadTextView.contentOffset.y, targetEditorOffset.y, accuracy: 1)
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
