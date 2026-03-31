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

func checklistActivationDocument() -> NotesSemanticDocument {
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
func checklistMarkerCharacterIndex(in textView: NSTextView) throws -> Int {
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
func checklistMarkerCharacterIndex(in textView: UITextView) throws -> Int {
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

func checklistItemTextCharacterIndex(
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

func checklistActivationNoteWithTrailingContent() -> NotePayload {
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
