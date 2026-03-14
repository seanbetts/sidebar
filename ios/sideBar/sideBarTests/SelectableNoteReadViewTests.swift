import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewTests: XCTestCase {
    func testReadBaseFontSizeMatchesAppBodyTextSize() {
        XCTAssertEqual(
            SelectableNoteReadView.readBaseFontSize(for: .large),
            NoteTextTypography.defaultBodyFontSize(for: .large),
            accuracy: 0.001
        )
        XCTAssertEqual(
            SelectableNoteReadView.readBaseFontSize(for: .small),
            NoteTextTypography.defaultBodyFontSize(for: .small),
            accuracy: 0.001
        )
    }

    func testMakePlatformAttributedContentPreservesDistinctBlockTypography() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let titleFont = try noteReadPlatformFont(in: attributed, at: 0)
        let headingFont = try noteReadPlatformFont(in: attributed, at: 6)
        let subheadingFont = try noteReadPlatformFont(in: attributed, at: 14)

        XCTAssertEqual(attributed.string, "Title\nHeading\nSubheading")
        XCTAssertGreaterThan(noteReadPlatformFontPointSize(titleFont), noteReadPlatformFontPointSize(headingFont))
        XCTAssertGreaterThan(noteReadPlatformFontPointSize(headingFont), noteReadPlatformFontPointSize(subheadingFont))
    }

    #if os(iOS)
    func testCharacterOffsetForEditingActivationKeepsReadTextViewOnTextKit2() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try lineEndOverflowClickPoint(in: textView, characterIndex: 2)

        XCTAssertNotNil(textView.textLayoutManager)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, 3)
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testCharacterOffsetForEditingActivationClampsTapBelowContentToEndOfNoteOnIOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try belowContentClickPoint(in: textView, characterIndex: 6)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, textView.text.utf16.count)
        XCTAssertNotNil(textView.textLayoutManager)
    }

    func testReadSurfaceUsesZeroInternalTextViewPaddingOnIOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: CGRect(x: 0, y: 0, width: 320, height: 120)
        )

        XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset, .zero)
    }

    func testMakePlatformAttributedContentUsesDynamicLabelColorOnIOS() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "Hello")
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let color = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            color.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
    }
    #endif

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

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in }
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

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in activationCount += 1 }
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
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in activationCount += 1 }
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

    func testMakePlatformTextViewInstallsActivationClickRecognizer() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Selectable text", marks: [])
                ])
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in }
        )

        let clickRecognizers = textView.gestureRecognizers.compactMap { $0 as? NSClickGestureRecognizer }

        XCTAssertEqual(clickRecognizers.count, 1)
        XCTAssertEqual(clickRecognizers.first?.numberOfClicksRequired, 1)
    }

    func testMakePlatformAttributedContentPreservesBoldItalicUnderlineAndBaseSize() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " ", marks: []),
                    .init(text: "Italic", marks: [.italic]),
                    .init(text: " ", marks: []),
                    .init(text: "Underlined", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 17
        )

        let boldFont = try XCTUnwrap(
            attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(notePlatformFontTraits(from: boldFont).bold)
        XCTAssertEqual(boldFont.pointSize, 17, accuracy: 0.001)

        let italicFont = try XCTUnwrap(
            attributed.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(notePlatformFontTraits(from: italicFont).italic)
        XCTAssertEqual(italicFont.pointSize, 17, accuracy: 0.001)

        let underlineValue = attributed.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int
        XCTAssertEqual(underlineValue, NSUnderlineStyle.single.rawValue)
    }

    func testBridgedPlatformFontTraitsDoNotAddFormattingWithoutSwiftUIFont() throws {
        var attributed = AttributedString("Bold Italic Underline")

        let boldEnd = attributed.index(attributed.startIndex, offsetByCharacters: 4)
        let italicStart = attributed.index(boldEnd, offsetByCharacters: 1)
        let italicEnd = attributed.index(italicStart, offsetByCharacters: 6)
        let underlineStart = attributed.index(italicEnd, offsetByCharacters: 1)

        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: true, italic: false),
            to: &attributed,
            range: attributed.startIndex..<boldEnd
        )
        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: false, italic: true),
            to: &attributed,
            range: italicStart..<italicEnd
        )
        attributed[underlineStart..<attributed.endIndex].underlineStyle = .single

        let rendered = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: attributed,
            baseFontSize: 16
        )

        let boldFont = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(notePlatformFontTraits(from: boldFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: boldFont).italic)

        let italicFont = try XCTUnwrap(
            rendered.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        )
        XCTAssertFalse(notePlatformFontTraits(from: italicFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: italicFont).italic)

        let underlineValue = rendered.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int
        XCTAssertEqual(underlineValue, NSUnderlineStyle.single.rawValue)
    }

    func testSwiftUIFontTraitsOverrideConflictingBridgedPlatformFontTraits() throws {
        var attributed = AttributedString("Italic")
        let range = attributed.startIndex..<attributed.endIndex
        attributed[range].font = noteInlineFont(baseFontSize: 16, bold: false, italic: true)
        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: true, italic: false),
            to: &attributed,
            range: range,
            clearSwiftUIFont: false
        )

        let rendered = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: attributed,
            baseFontSize: 16
        )

        let font = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = notePlatformFontTraits(from: font)
        XCTAssertFalse(traits.bold)
        XCTAssertTrue(traits.italic)
    }

    func testMakePlatformAttributedContentRemovesParagraphStyleOverrides() {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\n\nTwo")
        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        XCTAssertNil(readAttributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(readAttributed.attribute(.paragraphStyle, at: 4, effectiveRange: nil))
        XCTAssertNil(readAttributed.attribute(.paragraphStyle, at: 5, effectiveRange: nil))
    }

    func testReadTextViewBlankLineGapMatchesMountedEditorTextView() async throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\n\nTwo")
        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let readTextView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: readAttributed,
            onActivateEditing: { _ in }
        )
        readTextView.frame = NSRect(x: 0, y: 0, width: 420, height: 240)

        let editorTextView = try mountEditorTextView(
            plainText: "One\n\nTwo",
            baseFontSize: 16,
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        let readGap = try lineGap(in: readTextView, fromCharacterAt: 0, toCharacterAt: 5)
        let editorGap = try lineGap(in: editorTextView, fromCharacterAt: 0, toCharacterAt: 5)

        XCTAssertEqual(
            readGap,
            editorGap,
            accuracy: 1.0,
            "readGap=\(readGap) editorGap=\(editorGap)"
        )
    }

    func testCharacterOffsetForEditingActivationClampsTapToRightOfLineToVisualLineEnd() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try lineEndOverflowClickPoint(in: textView, characterIndex: 2)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, 3)
    }

    func testCharacterOffsetForEditingActivationClampsTapBelowContentToEndOfNote() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try belowContentClickPoint(in: textView, characterIndex: 6)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, textView.string.utf16.count)
    }
    #endif
}

private func noteReadPlatformFont(
    in attributed: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NoteReadPlatformFont {
    try XCTUnwrap(
        attributed.attribute(.font, at: location, effectiveRange: nil) as? NoteReadPlatformFont,
        file: file,
        line: line
    )
}

private func noteReadPlatformFontPointSize(_ font: NoteReadPlatformFont) -> CGFloat {
    #if os(macOS)
    font.pointSize
    #else
    font.pointSize
    #endif
}

#if os(macOS)
private typealias NoteReadPlatformFont = NSFont
#else
private typealias NoteReadPlatformFont = UIFont
#endif

@available(iOS 26.0, macOS 26.0, *)
private func makePlatformFont(
    baseFontSize: CGFloat,
    bold: Bool,
    italic: Bool
) -> NotePlatformFont {
    notePlatformFont(baseFontSize: baseFontSize, bold: bold, italic: italic)
}

@available(iOS 26.0, macOS 26.0, *)
private func applyBridgedPlatformFont(
    _ font: NotePlatformFont,
    to attributed: inout AttributedString,
    range: Range<AttributedString.Index>,
    clearSwiftUIFont: Bool = true
) {
    let plainText = String(attributed.characters)
    let lowerCharacterOffset = attributed.characters.distance(from: attributed.startIndex, to: range.lowerBound)
    let upperCharacterOffset = attributed.characters.distance(from: attributed.startIndex, to: range.upperBound)
    let lower = plainText.index(plainText.startIndex, offsetBy: lowerCharacterOffset)
    let upper = plainText.index(plainText.startIndex, offsetBy: upperCharacterOffset)
    let nsRange = NSRange(
        location: lower.utf16Offset(in: plainText),
        length: upper.utf16Offset(in: plainText) - lower.utf16Offset(in: plainText)
    )
    let bridged = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
    bridged.addAttribute(.font, value: font, range: nsRange)
    guard let bridgedAttributed = try? AttributedString(bridged, including: \.noteTextEditor) else {
        XCTFail("Expected bridged attributed string to remain convertible")
        return
    }
    attributed = bridgedAttributed
    if clearSwiftUIFont {
        attributed[range].font = nil
    }
}
