#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorCodeBlockSpacingTests: XCTestCase {
    func testReadAndEditorSurfacesAddVerticalPaddingAroundCodeBlocksOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1\nprint(x)", marks: [])]),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let minimumExtraBoundaryGap: CGFloat = (baseFontSize * 0.5) - 0.5

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let readTextView = makeReadTextView(
            attributedContent: readAttributed,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )
        let editorTextView = try makeEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )

        let readGapAbove = try lineGap(in: readTextView, fromCharacterAt: 0, toCharacterAt: 7)
        let readInternalGap = try lineGap(in: readTextView, fromCharacterAt: 7, toCharacterAt: 17)
        let readGapBelow = try lineGap(in: readTextView, fromCharacterAt: 17, toCharacterAt: 26)
        let editorGapAbove = try lineGap(in: editorTextView, fromCharacterAt: 0, toCharacterAt: 7)
        let editorInternalGap = try lineGap(in: editorTextView, fromCharacterAt: 7, toCharacterAt: 17)
        let editorGapBelow = try lineGap(in: editorTextView, fromCharacterAt: 17, toCharacterAt: 26)

        XCTAssertGreaterThan(readGapAbove, readInternalGap + minimumExtraBoundaryGap)
        XCTAssertGreaterThan(readGapBelow, readInternalGap + minimumExtraBoundaryGap)
        XCTAssertGreaterThan(editorGapAbove, editorInternalGap + minimumExtraBoundaryGap)
        XCTAssertGreaterThan(editorGapBelow, editorInternalGap + minimumExtraBoundaryGap)
    }
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
    var constrained = NotesAttributedDocumentCodec.attributedString(
        from: document,
        baseFontSize: baseFontSize
    )
    NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&constrained)

    let textView = UITextView(frame: frame)
    textView.adjustsFontForContentSizeCategory = false
    textView.isEditable = true
    textView.isScrollEnabled = true
    textView.backgroundColor = .clear
    textView.attributedText = NSAttributedString(constrained)
    textView.setNeedsLayout()
    textView.layoutIfNeeded()
    return textView
}
#endif
