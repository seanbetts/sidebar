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
        let editorTextView = try await enterEditModeAndFindEditorTextView(
            context: context,
            controller: controller
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
        let restoredReadViewportAnchorY = actualViewportAnchorY(
            in: restoredReadTextView,
            targetOffset: expectation.targetOffset
        )
        try assertRestoredReadViewportAnchor(
            context: context,
            editorTextView: editorTextView,
            readContentOffsetDuringExitHold: readContentOffsetDuringExitHold,
            readTextViewDuringExitHold: readTextViewDuringExitHold,
            restoredReadTextView: restoredReadTextView,
            expectation: expectation,
            restoredReadViewportAnchorY: restoredReadViewportAnchorY
        )
    }

    func testEditToReadTransitionKeepsSemanticListTargetLineAtSameRelativePosition() async throws {
        let note = makeSemanticListViewportParityNote()
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)

        await waitUntil {
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            ) != nil
        }

        let initialReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let targetOffset = NSString(string: initialReadTextView.attributedText.string)
            .range(of: "Fifth Item").location
        XCTAssertNotEqual(targetOffset, NSNotFound)

        let editorTextView = try await enterEditModeAndFindEditorTextView(
            context: context,
            controller: controller
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
                abs($0 - expectation.expectedViewportAnchorY) <= 6
            } == true &&
                context.editorViewModel.pendingReadSurfaceViewportOffset == nil
        }

        let restoredReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let restoredReadViewportAnchorY = actualViewportAnchorY(
            in: restoredReadTextView,
            targetOffset: expectation.targetOffset
        )
        try assertRestoredReadViewportAnchor(
            context: context,
            editorTextView: editorTextView,
            readContentOffsetDuringExitHold: readContentOffsetDuringExitHold,
            readTextViewDuringExitHold: readTextViewDuringExitHold,
            restoredReadTextView: restoredReadTextView,
            expectation: expectation,
            restoredReadViewportAnchorY: restoredReadViewportAnchorY,
            accuracy: 6
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

    func testEditToReadExitHoldKeepsEditorVisibleUntilReadRestorationCompletes() async throws {
        let plainText = (0..<120)
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

        let editorTextView = try XCTUnwrap(
            findTextView(
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
                && context.makeView().isHoldingEditorSurfaceDuringReadExit
                && findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
                && findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) != nil
        }

        let heldReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let heldEditorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            )
        )

        XCTAssertGreaterThan(effectiveAlpha(of: heldEditorTextView), 0.9)
        XCTAssertLessThan(effectiveAlpha(of: heldReadTextView), 0.1)

        await waitUntil {
            context.makeView().isHoldingEditorSurfaceDuringReadExit == false
                && findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) == nil
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

        let editorTextView = try await enterEditModeAndFindEditorTextView(
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
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let readTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        await waitUntil(timeout: .seconds(2)) {
            context.makeView().isHoldingEditorSurfaceDuringReadExit == false &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) == nil
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertFalse(
            context.makeView().isHoldingEditorSurfaceDuringReadExit,
            "Expected read-exit hold to clear; pendingOffset=\(String(describing: context.editorViewModel.pendingReadSurfaceViewportOffset)) pendingTarget=\(String(describing: context.editorViewModel.pendingReadSurfaceViewportAnchorTarget)) pendingAnchorY=\(String(describing: context.editorViewModel.pendingReadSurfaceViewportAnchorY))"
        )
        XCTAssertFalse(readTextView.attributedText.string.contains("> "))
        XCTAssertEqual(readTextView.attributedText.string, "Blockquotes\n")
        XCTAssertNil(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
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
            expectedViewportAnchorY: editorTargetRect.midY - editorViewport.minY,
            editorTargetRect: editorTargetRect,
            targetOffset: targetOffset
        )
    }

    private func enterEditModeAndFindEditorTextView(
        context: NotesDetailViewTestContext,
        controller: UIViewController
    ) async throws -> UIKitNoteTextEditorSurface.AccessoryTextView {
        context.editorViewModel.enterEditMode()
        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }
        return try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
    }

    private func assertRestoredReadViewportAnchor(
        context: NotesDetailViewTestContext,
        editorTextView: UIKitNoteTextEditorSurface.AccessoryTextView,
        readContentOffsetDuringExitHold: CGPoint,
        readTextViewDuringExitHold: UITextView,
        restoredReadTextView: UITextView,
        expectation: ViewportExpectation,
        restoredReadViewportAnchorY: CGFloat?,
        accuracy: CGFloat = 2
    ) throws {
        XCTAssertEqual(
            try XCTUnwrap(restoredReadViewportAnchorY),
            expectation.expectedViewportAnchorY,
            accuracy: accuracy,
            failureMessage(
                editorTextView: editorTextView,
                readContentOffsetDuringExitHold: readContentOffsetDuringExitHold,
                readTextViewDuringExitHold: readTextViewDuringExitHold,
                restoredReadTextView: restoredReadTextView,
                restoration: context.editorViewModel.debugLastExitReadViewportRestoration,
                pendingReadSurfaceViewportOffset: context.editorViewModel.pendingReadSurfaceViewportOffset,
                pendingReadSurfaceViewportAnchorTarget: context.editorViewModel.pendingReadSurfaceViewportAnchorTarget,
                pendingReadSurfaceViewportAnchorY: context.editorViewModel.pendingReadSurfaceViewportAnchorY,
                editorTargetRect: expectation.editorTargetRect,
                expectedViewportAnchorY: expectation.expectedViewportAnchorY,
                restoredReadViewportAnchorY: restoredReadViewportAnchorY
            )
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

@MainActor
private func effectiveAlpha(of view: UIView?) -> CGFloat {
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

@MainActor
@available(iOS 26.0, *)
private func makeSemanticListViewportParityNote() -> NotePayload {
    let document = NotesSemanticDocument(
        version: NotesSemanticDocument.currentVersion,
        blocks: [
            .init(type: .title, content: [.init(text: "Test Note", marks: [])]),
            .init(type: .heading, content: [.init(text: "Introduction", marks: [])]),
            .paragraph([.init(
                text: String(repeating: "This is a test note demo paragraph that forces wrapping. ", count: 12),
                marks: []
            )]),
            .init(type: .heading, content: [.init(text: "Checklist", marks: [])]),
            .init(
                type: .unorderedList,
                children: [
                    .init(type: .listItem, content: [.init(text: "First Item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Second Item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Third Item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Fourth Item", marks: [])]),
                    .init(type: .listItem, content: [.init(text: "Fifth Item", marks: [])])
                ]
            ),
            .paragraph([.init(
                text: String(repeating: "Trailing paragraph text keeps the document tall enough for restoration. ", count: 18),
                marks: []
            )])
        ]
    )

    return NotePayload(
        id: "semantic-list-viewport-note",
        name: "Test Note",
        document: document,
        plainText: NotesSemanticDocumentProjection.plainText(from: document),
        path: "/semantic-list-viewport-note.md",
        modified: nil,
        created: nil
    )
}
#endif
