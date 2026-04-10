#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesReadModeViewportExitHoldTests: NotesDetailViewHostingTestCase {
    func testEditToReadExitHoldKeepsEditorVisibleUntilReadRestorationCompletes() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)

        context.editorViewModel.enterEditMode()
        await waitUntil {
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }

        let editorTextView = try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        editorTextView.setContentOffset(CGPoint(x: 0, y: 320), animated: false)
        drainNotesHostingRunLoop()

        environment.shortcutActionEvent = ShortcutActionEvent(
            action: .closeItem,
            section: .notes,
            pane: nil
        )

        await waitUntil {
            context.editorViewModel.presentationMode == .read
                && exitHoldFindTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
                && exitHoldFindTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) != nil
        }

        let heldReadTextView = try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let heldEditorTextView = try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            )
        )

        XCTAssertGreaterThan(exitHoldEffectiveAlpha(of: heldEditorTextView), 0.9)
        XCTAssertLessThan(exitHoldEffectiveAlpha(of: heldReadTextView), 0.1)

        await waitUntil {
            guard exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) == nil,
            let restoredReadTextView = exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            ) else {
                return false
            }
            return exitHoldEffectiveAlpha(of: restoredReadTextView) > 0.9
        }
    }

    func testTypedBlockquoteEscapeReleasesExitHoldAndShowsReadProjectionOnIOS() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Blockquotes", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let note = NotePayload(
            id: "typed-blockquote-note",
            name: "Blockquotes",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/typed-blockquote-note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let editorTextView = try await exitHoldEnterEditModeAndFindEditorTextView(
            context: context,
            controller: controller
        )
        let nativeViewModel = try XCTUnwrap(context.editorViewModel.attachedNativeEditorViewModel)

        noteAppendTypedText(">", to: nativeViewModel)
        XCTAssertTrue(nativeViewModel.handleTextReplacement(" "))
        drainNotesHostingRunLoop()

        XCTAssertTrue(editorTextView.attributedText.string.contains("> "))

        editorTextView.handleEscapeCommand()

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.presentationMode == .read &&
                exitHoldFindTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let readTextView = try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        await waitUntil(timeout: .seconds(2)) {
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) == nil
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertFalse(readTextView.attributedText.string.contains("> "))
        XCTAssertEqual(readTextView.attributedText.string, "Blockquotes\n")
        XCTAssertNil(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            )
        )
    }

    func testEditToReadExitHoldDoesNotRefocusHeldEditorAfterViewRefresh() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let note = makeTestNote(plainText: plainText)
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)

        _ = try await exitHoldEnterEditModeAndFindEditorTextView(
            context: context,
            controller: controller
        )

        environment.shortcutActionEvent = ShortcutActionEvent(
            action: .closeItem,
            section: .notes,
            pane: nil
        )

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.presentationMode == .read &&
                exitHoldFindTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }

        let heldEditorTextView = try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        XCTAssertFalse(heldEditorTextView.shouldAutofocus)
        XCTAssertFalse(heldEditorTextView.isFirstResponder)

        context.store.applyEditorUpdate(
            makeTestNote(
                id: note.id,
                plainText: plainText
            )
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        drainNotesHostingRunLoop()
        try? await Task.sleep(nanoseconds: 150_000_000)
        drainNotesHostingRunLoop()

        let refreshedHeldEditorTextView = exitHoldFindTextView(
            in: controller.view,
            accessibilityIdentifier: "notes-editor-text-view"
        ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        if let refreshedHeldEditorTextView {
            XCTAssertTrue(refreshedHeldEditorTextView === heldEditorTextView)
            let failureMessage =
                """
                Expected the hidden editor surface to stay unfocused during read-exit hold even if a later
                note refresh triggers another UIKit update.
                """
                + "shouldAutofocus=\(refreshedHeldEditorTextView.shouldAutofocus) "
                + "hasScheduledAutofocus=\(refreshedHeldEditorTextView.hasScheduledAutofocus) "
                + "windowAttached=\(refreshedHeldEditorTextView.window != nil)"
            XCTAssertFalse(
                refreshedHeldEditorTextView.isFirstResponder,
                failureMessage
            )
        }
    }

    private func exitHoldEnterEditModeAndFindEditorTextView(
        context: NotesDetailViewTestContext,
        controller: UIViewController
    ) async throws -> UIKitNoteTextEditorSurface.AccessoryTextView {
        context.editorViewModel.enterEditMode()
        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false &&
                exitHoldFindTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }
        return try XCTUnwrap(
            exitHoldFindTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
    }
}

@MainActor
private func exitHoldFindTextView(in view: UIView?, accessibilityIdentifier: String) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }
    for subview in view.subviews {
        if let match = exitHoldFindTextView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }
    return nil
}

@MainActor
private func exitHoldEffectiveAlpha(of view: UIView?) -> CGFloat {
    guard let view, view.isHidden == false else { return 0 }
    var currentView: UIView? = view
    var alpha: CGFloat = 1
    while let inspectedView = currentView {
        if inspectedView.isHidden {
            return 0
        }
        alpha *= inspectedView.alpha
        currentView = inspectedView.superview
    }
    return alpha
}
#endif
