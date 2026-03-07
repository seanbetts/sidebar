import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorSurfaceParityTests: XCTestCase {
    func testMakePlatformTextViewDoesNotAutoAdjustForContentSizeCategory() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\n\nTwo")
        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = makeReadTextView(
            attributedContent: readAttributed,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )

        XCTAssertEqual(textView.adjustsFontForContentSizeCategory, false)
    }

    func testConstrainedEditorDocumentAppliesBodyParagraphStyleAcrossBlankFormattedParagraphsOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Bold", marks: [.bold])]),
                .paragraph([.init(text: "", marks: [])]),
                .paragraph([.init(text: "Italic", marks: [.italic])])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Formatted Gap",
            document: document,
            plainText: "Bold\n\nItalic",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let editorDocument = try constrainedEditorDocument(
            document: note.document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize
        )
        let attributedEditorDocument = NSAttributedString(editorDocument)
        let expectedStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
            baseFontSize: NoteTextTypography.defaultBodyFontSize
        )

        XCTAssertEqual(attributedEditorDocument.string, "Bold\n\nItalic")
        try assertParagraphStyle(attributedEditorDocument, matches: expectedStyle, at: 0)
        try assertParagraphStyle(attributedEditorDocument, matches: expectedStyle, at: 4)
        try assertParagraphStyle(attributedEditorDocument, matches: expectedStyle, at: 6)
    }

    func testReadSurfaceFormattingMatchesEditorSurfaceForSameSemanticNoteOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " ", marks: []),
                    .init(text: "Italic", marks: [.italic]),
                    .init(text: " ", marks: []),
                    .init(text: "Underline", marks: [.underline])
                ])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let editDocument = try constrainedEditorDocument(
            document: document,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(readAttributed.string, String(editDocument.characters))
        XCTAssertEqual(readAttributed.string, "Bold Italic Underline")

        try assertMatchingFontTraits(readAttributed, editDocument, at: 0)
        try assertMatchingFontTraits(readAttributed, editDocument, at: 5)
        try assertMatchingUnderline(readAttributed, editDocument, at: 12)
    }

    func testReadSurfaceBoldFontMatchesMountedEditorSurfaceExactlyOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold])
                ])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let readFont = try fontAttribute(in: readAttributed, at: 0)
        let expectedFont = notePlatformBoldBodyFont(baseFontSize: baseFontSize)
        let readTraits = notePlatformFontTraits(from: readFont)

        XCTAssertEqual(readFont.fontName, expectedFont.fontName)
        XCTAssertEqual(readFont.pointSize, expectedFont.pointSize, accuracy: 0.001)
        XCTAssertEqual(readTraits.bold, true)
        XCTAssertEqual(readTraits.italic, false)
    }

    func testIOSCanMoveToUIKitEditorSurfaceWithoutChangingCanonicalParityContracts() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " ", marks: []),
                    .init(text: "Italic", marks: [.italic])
                ])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let editDocument = try constrainedEditorDocument(
            document: document,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(readAttributed.string, String(editDocument.characters))
        try assertMatchingFontTraits(readAttributed, editDocument, at: 0)
        try assertMatchingFontTraits(readAttributed, editDocument, at: 5)
        XCTAssertFalse(try attributedNoteEditorContainerMountsSwiftUISurfaceDirectly())
    }
}

private func assertMatchingFontTraits(
    _ lhs: NSAttributedString,
    _ rhs: AttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let lhsFont = try fontAttribute(in: lhs, at: location, file: file, line: line)
    let lhsTraits = notePlatformFontTraits(from: lhsFont)
    let rhsRange = singleCharacterRange(at: location, in: rhs, file: file, line: line)
    XCTAssertEqual(
        lhsTraits.bold,
        noteRangeHasBoldTrait(rhs, range: rhsRange),
        file: file,
        line: line
    )
    XCTAssertEqual(
        lhsTraits.italic,
        noteRangeHasItalicTrait(rhs, range: rhsRange),
        file: file,
        line: line
    )
}

private func assertMatchingUnderline(
    _ lhs: NSAttributedString,
    _ rhs: AttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let rhsRange = singleCharacterRange(at: location, in: rhs, file: file, line: line)
    XCTAssertEqual(
        try underlineAttribute(in: lhs, at: location, file: file, line: line),
        noteRangeIsUnderlined(rhs, range: rhsRange) ? NSUnderlineStyle.single.rawValue : nil,
        file: file,
        line: line
    )
}

@MainActor
private func constrainedEditorDocument(
    document: NotesSemanticDocument,
    baseFontSize: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> AttributedString {
    var constrained = NotesAttributedDocumentCodec.attributedString(
        from: document,
        baseFontSize: baseFontSize
    )
    NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&constrained)
    _ = (file, line)
    return constrained
}

private func fontAttribute(
    in attributedText: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UIFont {
    guard attributedText.length > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(attributedText.length)",
            file: file,
            line: line
        )
        throw NotesEditorSurfaceParityTestError.missingAttribute
    }

    return try XCTUnwrap(
        attributedText.attribute(.font, at: location, effectiveRange: nil) as? UIFont,
        file: file,
        line: line
    )
}

private func underlineAttribute(
    in attributedText: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Int? {
    guard attributedText.length > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(attributedText.length)",
            file: file,
            line: line
        )
        throw NotesEditorSurfaceParityTestError.missingAttribute
    }

    return attributedText.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int
}

private func assertParagraphStyle(
    _ attributedText: NSAttributedString,
    matches expected: NSParagraphStyle,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard attributedText.length > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(attributedText.length)",
            file: file,
            line: line
        )
        throw NotesEditorSurfaceParityTestError.missingAttribute
    }

    let actual = try XCTUnwrap(
        attributedText.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.lineSpacing, expected.lineSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(
        actual.paragraphSpacingBefore,
        expected.paragraphSpacingBefore,
        accuracy: 0.001,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.paragraphSpacing, expected.paragraphSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.headIndent, expected.headIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(
        actual.firstLineHeadIndent,
        expected.firstLineHeadIndent,
        accuracy: 0.001,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.tailIndent, expected.tailIndent, accuracy: 0.001, file: file, line: line)
}

private enum NotesEditorSurfaceParityTestError: Error {
    case missingAttribute
}

private func singleCharacterRange(
    at location: Int,
    in text: AttributedString,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Range<AttributedString.Index> {
    guard location >= 0, text.characters.count > location else {
        XCTFail(
            "Expected attributed text length > \(location), got \(text.characters.count)",
            file: file,
            line: line
        )
        return text.startIndex..<text.startIndex
    }

    let lower = text.index(text.startIndex, offsetByCharacters: location)
    let upper = text.index(afterCharacter: lower)
    return lower..<upper
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func lineGap(
    in textView: UITextView,
    fromCharacterAt firstIndex: Int,
    toCharacterAt secondIndex: Int
) throws -> CGFloat {
    let firstRect = try glyphRect(in: textView, characterIndex: firstIndex)
    let secondRect = try glyphRect(in: textView, characterIndex: secondIndex)
    return secondRect.minY - firstRect.maxY
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func glyphRect(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGRect {
    let layoutManager = textView.layoutManager
    let textContainer = textView.textContainer
    textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeReadTextView(
    attributedContent: NSAttributedString,
    frame: CGRect
) -> UITextView {
    let textView = UITextView(frame: frame)
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.adjustsFontForContentSizeCategory = false
    textView.attributedText = attributedContent
    textView.setNeedsLayout()
    textView.layoutIfNeeded()
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeEditorTextView(
    document: NotesSemanticDocument,
    baseFontSize: CGFloat,
    frame: CGRect
) throws -> UITextView {
    let textView = UITextView(frame: frame)
    textView.adjustsFontForContentSizeCategory = false
    textView.isEditable = true
    textView.isScrollEnabled = true
    textView.backgroundColor = .clear
    textView.attributedText = NSAttributedString(
        try constrainedEditorDocument(
            document: document,
            baseFontSize: baseFontSize
        )
    )
    textView.setNeedsLayout()
    textView.layoutIfNeeded()
    return textView
}
#endif
