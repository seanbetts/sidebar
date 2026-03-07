import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewTests: XCTestCase {
    func testMakeAttributedContentPreservesFormattingAndDetectsLinks() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Visit ", marks: []),
                    .init(text: "https://example.com", marks: [.bold]),
                    .init(text: " today", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makeAttributedContent(from: document, baseFontSize: 18)

        XCTAssertEqual(String(attributed.characters), "Visit https://example.com today")

        let linkStart = attributed.index(attributed.startIndex, offsetByCharacters: 6)
        let linkEnd = attributed.index(linkStart, offsetByCharacters: 19)
        XCTAssertTrue(noteRangeHasBoldTrait(attributed, range: linkStart..<linkEnd))

        let trailingStart = attributed.index(linkEnd, offsetByCharacters: 1)
        let trailingEnd = attributed.endIndex
        XCTAssertTrue(noteRangeIsUnderlined(attributed, range: trailingStart..<trailingEnd))

        let bridged = NSAttributedString(attributed)
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
        let linkValue = bridged.attribute(
            NSAttributedString.Key.link,
            at: 7,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)
    }

    #if os(macOS)
    func testMakePlatformTextViewIsSelectableAndNonEditable() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Copy https://example.com", marks: [])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makeAttributedContent(from: document, baseFontSize: 16)
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: {}
        )

        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.string, "Copy https://example.com")

        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
        let linkValue = textView.textStorage?.attribute(
            NSAttributedString.Key.link,
            at: 6,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)
    }

    func testMakePlatformTextViewKeepsFormattedDragSelectionsCopyableWithoutActivatingEditMode() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " and ", marks: []),
                    .init(text: "underlined", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makeAttributedContent(from: document, baseFontSize: 16)
        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { activationCount += 1 }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)

        let dragStart = try makeSelectionPoint(
            in: textView,
            characterIndex: 0,
            horizontalBias: 0.05
        )
        let dragEnd = try makeSelectionPoint(
            in: textView,
            characterIndex: textView.string.utf16.count - 1,
            horizontalBias: 0.95
        )
        try performDragSelection(in: textView, from: dragStart, to: dragEnd)

        let selected = try exportedSelection(from: textView)

        XCTAssertEqual(activationCount, 0)
        XCTAssertGreaterThan(textView.selectedRange().length, 0)
        XCTAssertEqual(String(selected.characters), "Bold and underlined")
        XCTAssertTrue(noteRangeHasBoldTrait(selected, range: noteCharacterRange(length: 4, in: selected)))

        let underlineStart = selected.index(selected.startIndex, offsetByCharacters: 9)
        XCTAssertTrue(noteRangeIsUnderlined(selected, range: underlineStart..<selected.endIndex))
    }

    func testMakePlatformTextViewFiresEditActivationAfterSingleClick() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Selectable text", marks: [.bold])
                ])
            ]
        )
        let attributed = SelectableNoteReadView.makeAttributedContent(from: document, baseFontSize: 16)

        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { activationCount += 1 }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)

        let clickPoint = try XCTUnwrap(nonLinkClickPoint(in: textView, characterIndex: 0))
        let mouseDown = try makeMouseEvent(
            type: .leftMouseDown,
            location: clickPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        )
        let mouseUp = try makeMouseEvent(
            type: .leftMouseUp,
            location: clickPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        )

        textView.mouseDown(with: mouseDown)
        textView.mouseUp(with: mouseUp)

        XCTAssertEqual(activationCount, 1)
    }
    #endif
}

#if os(macOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func nonLinkClickPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat = 0.5
) -> NSPoint? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer,
          characterIndex < textView.string.utf16.count else {
        return nil
    }

    textContainer.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
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
private func makeMouseEvent(
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

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeSelectionPoint(
    in textView: NSTextView,
    characterIndex: Int,
    horizontalBias: CGFloat
) throws -> NSPoint {
    try XCTUnwrap(
        nonLinkClickPoint(
            in: textView,
            characterIndex: characterIndex,
            horizontalBias: horizontalBias
        )
    )
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func performDragSelection(
    in textView: NSTextView,
    from start: NSPoint,
    to end: NSPoint
) throws {
    let mouseDown = try makeMouseEvent(
        type: .leftMouseDown,
        location: start,
        timestamp: 0,
        eventNumber: 0,
        pressure: 1
    )
    let mouseDragged = try makeMouseEvent(
        type: .leftMouseDragged,
        location: end,
        timestamp: 0.1,
        eventNumber: 1,
        pressure: 1
    )
    let mouseUp = try makeMouseEvent(
        type: .leftMouseUp,
        location: end,
        timestamp: 0.2,
        eventNumber: 2,
        pressure: 0
    )

    textView.mouseDown(with: mouseDown)
    textView.mouseDragged(with: mouseDragged)
    textView.mouseUp(with: mouseUp)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func exportedSelection(from textView: NSTextView) throws -> AttributedString {
    let exported = try XCTUnwrap(
        textView.attributedSubstring(
            forProposedRange: textView.selectedRange(),
            actualRange: nil
        )
    )
    return AttributedString(exported)
}
#endif
