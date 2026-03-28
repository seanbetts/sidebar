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
        let checkboxPoint = try checklistClickPoint(
            in: textView,
            characterIndex: 8,
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
        let textPoint = try checklistClickPoint(
            in: textView,
            characterIndex: 12,
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
        let containerView: UIView = try XCTUnwrap(textView.superview)
        let tapPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: 8,
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
        let containerView: UIView = try XCTUnwrap(textView.superview)
        let tapPoint = try checklistLocalTapPoint(
            in: textView,
            characterIndex: 12,
            horizontalBias: 0.5
        )
        let recognizer = ReadChecklistTapRecognizer(location: tapPoint)
        recognizer.setValue(UIGestureRecognizer.State.ended.rawValue, forKey: "state")

        containerView.perform(
            NSSelectorFromString("handleActivationTapGesture:"),
            with: recognizer
        )

        XCTAssertEqual(capturedTarget, .characterOffset(12))
        XCTAssertFalse(didToggleChecklistItem)
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
    guard let start = textView.position(from: textView.beginningOfDocument, offset: characterIndex),
          let end = textView.position(from: start, offset: 1),
          let textRange = textView.textRange(from: start, to: end) else {
        throw XCTSkip("Unable to resolve tap point")
    }

    let characterRect = textView.firstRect(for: textRange)
    guard characterRect.isNull == false, characterRect.isEmpty == false else {
        throw XCTSkip("Unable to resolve tap point")
    }

    return CGPoint(
        x: characterRect.minX + (characterRect.width * horizontalBias),
        y: characterRect.midY
    )
}

private func checklistFindDescendantTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }

    for subview in view.subviews {
        if let match = checklistFindDescendantTextView(in: subview) {
            return match
        }
    }

    return nil
}

private final class ReadChecklistTapRecognizer: UITapGestureRecognizer, @unchecked Sendable {
    private let testLocation: CGPoint

    init(location: CGPoint) {
        self.testLocation = location
        super.init(target: nil, action: nil)
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
