import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import SwiftUI
import UIKit
#endif
@testable import sideBar

#if os(macOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class ReadChecklistActivationTests: XCTestCase {
    func testChecklistClickPointsResolveExpectedCharacterOffsets() async throws {
        let document = checklistActivationDocument()
        let textView = try makeChecklistReadActivationTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            onActivateEditing: { _ in }
        )
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: textView)
        let textCharacterIndex = try checklistItemTextCharacterIndex(in: textView)
        let checkboxPoint = try checklistClickPoint(
            in: textView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )
        let textPoint = try checklistClickPoint(
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
            8
        )
    }

    func testChecklistCheckboxClickTogglesInsteadOfActivatingEditing() async throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var capturedToggle: (blockIndex: Int, itemIndex: Int)?
        let document = checklistActivationDocument()
        let textView = try makeChecklistReadActivationTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            onActivateEditing: { target in
                capturedTarget = target
            },
            onToggleChecklistItem: { blockIndex, itemIndex in
                capturedToggle = (blockIndex, itemIndex)
            }
        )
        let checkboxCharacterIndex = try checklistMarkerCharacterIndex(in: textView)
        let checkboxPoint = try checklistClickPoint(
            in: textView,
            characterIndex: checkboxCharacterIndex,
            horizontalBias: 0.5
        )

        textView.mouseDown(with: try checklistActivationMouseEvent(
            type: .leftMouseDown,
            location: checkboxPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        ))
        textView.mouseUp(with: try checklistActivationMouseEvent(
            type: .leftMouseUp,
            location: checkboxPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        ))

        for _ in 0..<3 {
            drainNotesHostingRunLoop()
            await Task.yield()
        }

        XCTAssertEqual(capturedToggle?.blockIndex, 1)
        XCTAssertEqual(capturedToggle?.itemIndex, 0)
        XCTAssertNil(capturedTarget)
    }

    func testChecklistTextClickStillActivatesEditing() async throws {
        var capturedTarget: NotesEditorViewModel.PendingEditSelectionTarget?
        var didToggleChecklistItem = false
        let document = checklistActivationDocument()
        let textView = try makeChecklistReadActivationTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            onActivateEditing: { target in
                capturedTarget = target
            },
            onToggleChecklistItem: { _, _ in
                didToggleChecklistItem = true
            }
        )
        let textCharacterIndex = try checklistItemTextCharacterIndex(in: textView)
        let textPoint = try checklistClickPoint(
            in: textView,
            characterIndex: textCharacterIndex,
            horizontalBias: 0.5
        )

        textView.mouseDown(with: try checklistActivationMouseEvent(
            type: .leftMouseDown,
            location: textPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        ))
        textView.mouseUp(with: try checklistActivationMouseEvent(
            type: .leftMouseUp,
            location: textPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        ))

        for _ in 0..<3 {
            drainNotesHostingRunLoop()
            await Task.yield()
        }

        XCTAssertEqual(capturedTarget, .characterOffset(12))
        XCTAssertFalse(didToggleChecklistItem)
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeChecklistReadActivationTextView(
    document: NotesSemanticDocument,
    frame: NSRect,
    onActivateEditing: @escaping (NotesEditorViewModel.PendingEditSelectionTarget) -> Void,
    onToggleChecklistItem: @escaping (Int, Int) -> Void = { _, _ in }
) throws -> NSTextView {
    let attributed = SelectableNoteReadView.makePlatformAttributedContent(
        from: document,
        baseFontSize: 16
    )
    let textView = SelectableNoteReadView.makePlatformTextView(
        attributedContent: attributed,
        document: document,
        onActivateEditing: onActivateEditing,
        onToggleChecklistItem: onToggleChecklistItem
    )
    textView.frame = frame
    textView.layoutSubtreeIfNeeded()
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func checklistClickPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> NSPoint {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          characterIndex < textView.string.utf16.count else {
        throw XCTSkip("Unable to resolve click point")
    }

    textContainer.containerSize = NSSize(
        width: textView.bounds.width,
        height: CGFloat.greatestFiniteMagnitude
    )
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
    return NSPoint(
        x: textView.textContainerInset.width + glyphRect.minX + (glyphRect.width * horizontalBias),
        y: textView.textContainerInset.height + glyphRect.midY
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func checklistActivationMouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    timestamp: TimeInterval,
    eventNumber: Int,
    pressure: Float
) throws -> NSEvent {
    try XCTUnwrap(
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: pressure
        )
    )
}
#endif

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

private func checklistActivationDocument() -> NotesSemanticDocument {
    NotesSemanticDocument(
        version: NotesSemanticDocument.currentVersion,
        blocks: [
            .init(type: .title, content: [.init(text: "Title", marks: [])]),
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "Done item", marks: [])], checked: false)
                ]
            )
        ]
    )
}

#if os(macOS)
private func checklistMarkerCharacterIndex(in textView: NSTextView) throws -> Int {
    let attributed = try XCTUnwrap(textView.textStorage)
    for index in 0..<attributed.length where attributed.attribute(.attachment, at: index, effectiveRange: nil) != nil {
        return index
    }

    let string = attributed.string as NSString
    let checkedRange = string.range(of: "[x]")
    if checkedRange.location != NSNotFound {
        return checkedRange.location
    }

    let uncheckedRange = string.range(of: "[ ]")
    guard uncheckedRange.location != NSNotFound else {
        throw XCTSkip("Unable to resolve checklist marker")
    }
    return uncheckedRange.location
}
#elseif os(iOS)
private func checklistMarkerCharacterIndex(in textView: UITextView) throws -> Int {
    let attributed = try XCTUnwrap(textView.attributedText)
    for index in 0..<attributed.length where attributed.attribute(.attachment, at: index, effectiveRange: nil) != nil {
        return index
    }

    let string = attributed.string as NSString
    let checkedRange = string.range(of: "[x]")
    if checkedRange.location != NSNotFound {
        return checkedRange.location
    }

    let uncheckedRange = string.range(of: "[ ]")
    guard uncheckedRange.location != NSNotFound else {
        throw XCTSkip("Unable to resolve checklist marker")
    }
    return uncheckedRange.location
}
#endif

private func checklistItemTextCharacterIndex(
    in textView: some NSObject
) throws -> Int {
    #if os(macOS)
    if let macTextView = textView as? NSTextView {
        let markerIndex = try checklistMarkerCharacterIndex(in: macTextView)
        if macTextView.textStorage?.attribute(.attachment, at: markerIndex, effectiveRange: nil) != nil {
            return markerIndex + 2
        }

        let string = macTextView.string as NSString
        let textRange = string.range(of: "Done item")
        guard textRange.location != NSNotFound else {
            throw XCTSkip("Unable to resolve checklist text")
        }
        return textRange.location
    }
    #endif

    #if os(iOS)
    if let iosTextView = textView as? UITextView {
        let attributed = try XCTUnwrap(iosTextView.attributedText)
        let markerIndex = try checklistMarkerCharacterIndex(in: iosTextView)
        if attributed.attribute(.attachment, at: markerIndex, effectiveRange: nil) != nil {
            return markerIndex + 2
        }

        let string = attributed.string as NSString
        let textRange = string.range(of: "Done item")
        guard textRange.location != NSNotFound else {
            throw XCTSkip("Unable to resolve checklist text")
        }
        return textRange.location
    }
    #endif

    throw XCTSkip("Unsupported text view")
}

private func checklistActivationNoteWithTrailingContent() -> NotePayload {
    let document = NotesSemanticDocument(
        version: NotesSemanticDocument.currentVersion,
        blocks: [
            .init(type: .title, content: [.init(text: "Title", marks: [])]),
            .init(
                type: .checklist,
                children: [
                    .init(type: .listItem, content: [.init(text: "Done item", marks: [])], checked: false)
                ]
            ),
            .paragraph([.init(text: String(repeating: "Trailing paragraph text. ", count: 40), marks: [])])
        ]
    )

    return NotePayload(
        id: "checklist-mounted-detail-note",
        name: "Title",
        document: document,
        plainText: NotesSemanticDocumentProjection.plainText(from: document),
        path: "/checklist-mounted-detail-note.md",
        modified: nil,
        created: nil
    )
}
