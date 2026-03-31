import XCTest
#if os(iOS)
import SwiftUI
import UIKit
#endif
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
final class ReadChecklistActivationIOSTests: NotesDetailViewHostingTestCase {
    func testChecklistTapPointsResolveExpectedCharacterOffsetsOnIOS() throws {
        let document = checklistActivationDocument()

        let controller = mount(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: 320,
                onActivateEditing: { _ in }
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(checklistFindDescendantTextView(in: controller.view))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: textView)
        let textCharacterIndex = try checklistItemTextCharacterIndex(in: textView)

        let checkboxPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        let textPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: textCharacterIndex,
            horizontalBias: 0.5
        )

        XCTAssertEqual(
            SelectableNoteReadView.characterOffsetForEditingActivation(in: textView, at: checkboxPoint),
            6
        )
        XCTAssertEqual(
            SelectableNoteReadView.characterOffsetForEditingActivation(in: textView, at: textPoint),
            9
        )
    }

    func testChecklistCheckboxTapTogglesInsteadOfActivatingEditing() throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var capturedToggle: (blockIndex: Int, itemIndex: Int)?
        let document = checklistActivationDocument()

        let controller = mount(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: 320,
                onActivateEditing: { target in
                    capturedTarget = target
                },
                onToggleChecklistItem: { blockIndex, itemIndex in
                    capturedToggle = (blockIndex, itemIndex)
                }
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(checklistFindDescendantTextView(in: controller.view))
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: textView))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: textView)
        let tapPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        XCTAssertEqual(capturedToggle?.blockIndex, 1)
        XCTAssertEqual(capturedToggle?.itemIndex, 0)
        XCTAssertNil(capturedTarget)
    }

    func testChecklistTextTapStillActivatesEditing() throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var didToggleChecklistItem = false
        let document = checklistActivationDocument()

        let controller = mount(
            SelectableNoteReadView(
                document: document,
                maxContentWidth: 320,
                onActivateEditing: { target in
                    capturedTarget = target
                },
                onToggleChecklistItem: { _, _ in
                    didToggleChecklistItem = true
                }
            ),
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            makeKeyAndVisible: true
        )
        let textView = try XCTUnwrap(checklistFindDescendantTextView(in: controller.view))
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: textView))
        let textCharacterIndex = try checklistItemTextCharacterIndex(in: textView)
        let tapPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: textCharacterIndex,
            horizontalBias: 0.5
        )
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        XCTAssertEqual(capturedTarget, .characterOffset(13))
        XCTAssertFalse(didToggleChecklistItem)
    }

    func testReadModeChecklistToggleDoesNotBlockSubsequentEditEntryOnMountedDetailView() async throws {
        let note = checklistActivationNoteWithTrailingContent()
        let notePlainText = NSString(string: note.plainText)
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        await context.editorViewModel.toggleChecklistItemInReadMode(
            blockIndex: 1,
            itemIndex: 0
        )

        await waitUntil {
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked == true
        }

        let updatedReadTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let targetOffset = notePlainText.range(of: "Done item").location + 2
        let readTargetPosition = try XCTUnwrap(
            updatedReadTextView.position(from: updatedReadTextView.beginningOfDocument, offset: targetOffset)
        )
        let readTargetRect = updatedReadTextView.caretRect(for: readTargetPosition)
        let readViewport = updatedReadTextView.bounds.inset(by: updatedReadTextView.adjustedContentInset)
        let viewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: viewportAnchorY
        )

        await waitUntil {
            checklistFindDescendantEditorTextView(in: controller.view) != nil
        }

        let editorTextView = try XCTUnwrap(checklistFindDescendantEditorTextView(in: controller.view))
        let initialEditorOffset = editorTextView.contentOffset.y
        let targetEditorOffset = min(
            initialEditorOffset + 120,
            max(
                editorTextView.contentSize.height
                    + editorTextView.adjustedContentInset.bottom
                    - editorTextView.bounds.height,
                -editorTextView.adjustedContentInset.top
            )
        )

        editorTextView.setContentOffset(CGPoint(x: 0, y: targetEditorOffset), animated: false)
        drainNotesHostingRunLoop()

        XCTAssertTrue(context.editorViewModel.isEditingNote)
        XCTAssertEqual(editorTextView.contentOffset.y, targetEditorOffset, accuracy: 1)
    }

    func testMountedDetailViewCheckboxTapTogglesChecklistItemInReadMode() async throws {
        let note = checklistActivationNoteWithTrailingContent()
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: readTextView))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: readTextView)
        let tapPoint = try checklistLocalTapPoint(
            in: readTextView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        await waitUntil(timeout: .milliseconds(250)) {
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked == true
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked,
            true
        )
    }

    func testMountedDetailViewCheckboxTapTogglesFromUpperHalfOfSymbol() async throws {
        let note = checklistActivationNoteWithTrailingContent()
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: readTextView))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: readTextView)
        var tapPoint = try checklistLocalTapPoint(
            in: readTextView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        tapPoint.y -= 6
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        await waitUntil(timeout: .milliseconds(250)) {
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked == true
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked,
            true
        )
    }

    func testMountedDetailViewCheckboxTapTogglesFromLowerHalfOfSymbol() async throws {
        let note = checklistActivationNoteWithTrailingContent()
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: readTextView))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: readTextView)
        var tapPoint = try checklistLocalTapPoint(
            in: readTextView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        tapPoint.y += 6
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        await waitUntil(timeout: .milliseconds(250)) {
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked == true
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked,
            true
        )
    }

    func testMountedDetailViewCheckboxTapTogglesFromLeadingEdgeOfSymbol() async throws {
        let note = checklistActivationNoteWithTrailingContent()
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            checklistFindDescendantTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let containerView = try XCTUnwrap(checklistActivationContainerView(for: readTextView))
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: readTextView)
        var tapPoint = try checklistLocalTapPoint(
            in: readTextView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        tapPoint.x -= 6
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        await waitUntil(timeout: .milliseconds(250)) {
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked == true
        }

        XCTAssertEqual(context.editorViewModel.presentationMode, .read)
        XCTAssertEqual(
            context.editorViewModel.currentSemanticDocumentSnapshot()
                .blocks[1]
                .children?.first?.checked,
            true
        )
    }
}

@MainActor
@available(iOS 26.0, *)
private func checklistLocalTapPoint(
    in textView: UITextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> CGPoint {
    guard characterIndex < textView.attributedText.length else {
        throw XCTSkip("Unable to resolve tap point")
    }
    guard let start = textView.position(from: textView.beginningOfDocument, offset: characterIndex) else {
        throw XCTSkip("Unable to resolve tap point")
    }

    let characterRect: CGRect
    if let end = textView.position(from: start, offset: 1),
       let textRange = textView.textRange(from: start, to: end) {
        let firstRect = textView.firstRect(for: textRange)
        characterRect = firstRect.isNull == false && firstRect.isEmpty == false
            ? firstRect
            : textView.caretRect(for: start)
    } else {
        characterRect = textView.caretRect(for: start)
    }
    guard characterRect.isNull == false, characterRect.isEmpty == false else {
        throw XCTSkip("Unable to resolve tap point")
    }

    return CGPoint(
        x: characterRect.minX + (characterRect.width * horizontalBias),
        y: characterRect.midY
    )
}

private func checklistFindDescendantTextView(
    in view: UIView,
    accessibilityIdentifier: String? = nil
) -> UITextView? {
    if let textView = view as? UITextView,
       accessibilityIdentifier == nil || textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }

    for subview in view.subviews {
        if let match = checklistFindDescendantTextView(
            in: subview,
            accessibilityIdentifier: accessibilityIdentifier
        ) {
            return match
        }
    }

    return nil
}

private func checklistActivationContainerView(
    for textView: UIView
) -> UIView? {
    let selector = NSSelectorFromString("handleActivationTapGesture:")
    var currentView: UIView? = textView

    while let view = currentView {
        if view.responds(to: selector) {
            return view
        }
        currentView = view.superview
    }

    return nil
}

private func checklistFindDescendantEditorTextView(
    in view: UIView
) -> UIKitNoteTextEditorSurface.AccessoryTextView? {
    if let textView = view as? UIKitNoteTextEditorSurface.AccessoryTextView {
        return textView
    }

    for subview in view.subviews {
        if let match = checklistFindDescendantEditorTextView(in: subview) {
            return match
        }
    }

    return nil
}

private final class ReadChecklistTapRecognizer: UITapGestureRecognizer, @unchecked Sendable {
    private let testLocation: CGPoint
    private var forcedState: UIGestureRecognizer.State = .ended

    init(location: CGPoint) {
        self.testLocation = location
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { forcedState }
        set { forcedState = newValue }
    }

    override func location(in view: UIView?) -> CGPoint {
        testLocation
    }
}
#endif
