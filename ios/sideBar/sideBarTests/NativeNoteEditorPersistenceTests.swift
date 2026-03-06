import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorPersistenceTests: XCTestCase {
    func testCurrentPersistenceSnapshotExportsPlainTextAndCanonicalRTF() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.plainText, "hello")
        XCTAssertFalse(snapshot.canonicalContent.isEmpty)
        XCTAssertEqual(
            NotesRichTextCodec.decodeBase64RTFToPlainText(snapshot.canonicalContent),
            "hello"
        )
    }

    func testCurrentPersistenceSnapshotPreservesProjectedPlainTextLineBreaks() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("line 1\n\nline 3")

        let snapshot = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(snapshot.plainText, "line 1\n\nline 3")
    }

    func testPersistenceSnapshotRoundTripPreservesBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.bold)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let hasBoldFont = reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldFont)
    }

    func testPersistenceSnapshotRoundTripPreservesTraitOnlyBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.bold)
        viewModel.attributedContent[fullRange].inlinePresentationIntent = []

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let hasBoldFont = reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = bridgedPlatformFont(from: run) as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldFont)
    }

    func testPersistenceSnapshotMaterializesSemanticOnlyBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.attributedContent[fullRange].inlinePresentationIntent = [.stronglyEmphasized]

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        })
    }

    func testPersistenceSnapshotMaterializesSemanticOnlyItalicFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.attributedContent[fullRange].inlinePresentationIntent = [.emphasized]

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = bridgedPlatformFont(from: run) as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.italic)
            #endif
        })
    }

    func testPersistenceSnapshotRoundTripPreservesItalicFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.italic)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = bridgedPlatformFont(from: run) as? UIFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.italic)
            #endif
        })
    }

    func testPersistenceSnapshotRoundTripPreservesUnderlineFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.underline)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(reloaded.attributedContent.runs.contains { run in
            run.underlineStyle == .single
        })
    }

    func testPersistenceSnapshotRoundTripPreservesInsertionPointTypingFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        viewModel.applyFormatting(.bold)
        viewModel.applyFormatting(.italic)
        viewModel.applyFormatting(.underline)
        appendTypedText("A", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let firstRun = reloaded.attributedContent.runs.first
        XCTAssertNotNil(firstRun)
        XCTAssertEqual(firstRun?.underlineStyle, .single)
        #if os(iOS)
        let font = firstRun?[AttributeScopes.UIKitAttributes.FontAttribute.self]
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true)
        #elseif os(macOS)
        let font = firstRun.flatMap { bridgedPlatformFont(from: $0) as? NSFont }
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #endif
    }

    func testLoadTextEmptySeedsParagraphTypingAttributes() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let attrs = viewModel.defaultTypingAttributes()
        XCTAssertEqual(attrs.blockKind, .paragraph)
        XCTAssertNotNil(attrs.paragraphStyle)
        XCTAssertNotNil(attrs.font)
    }

    func testLoadDocumentNormalizesToCurrentBaseFontSize() async {
        let source = NativeNoteEditorViewModel()
        source.setBaseFontSize(14)
        source.loadText("hello")
        let snapshot = source.currentPersistenceSnapshot()

        let reloaded = NativeNoteEditorViewModel()
        reloaded.setBaseFontSize(22)
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let pointSize = firstRunPointSize(in: reloaded.attributedContent)
        XCTAssertNotNil(pointSize)
        XCTAssertEqual(pointSize ?? 0, 22, accuracy: 1.0)
    }

    func testLoadTextDoesNotInferMarkdownStructureFromLiteralPrefixes() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("# Heading\n- bullet\n> quote")

        let ranges = lineRanges(in: viewModel.attributedContent)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: ranges[0]), .paragraph)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: ranges[1]), .paragraph)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: ranges[2]), .paragraph)
        XCTAssertNil(viewModel.attributedContent[ranges[0]].listDepth)
        XCTAssertNil(viewModel.attributedContent[ranges[1]].listDepth)
        XCTAssertNil(viewModel.attributedContent[ranges[2]][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func characterRange(
    length: Int,
    in text: AttributedString
) -> Range<AttributedString.Index> {
    var index = text.startIndex
    for _ in 0..<length {
        index = text.index(afterCharacter: index)
    }
    return text.startIndex..<index
}

@available(iOS 26.0, macOS 26.0, *)
private func firstRunPointSize(in text: AttributedString) -> CGFloat? {
    for run in text.runs {
        #if os(iOS)
        if let font = bridgedPlatformFont(from: run) as? UIFont {
            return font.pointSize
        }
        #elseif os(macOS)
        if let font = bridgedPlatformFont(from: run) as? NSFont {
            return font.pointSize
        }
        #endif
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
    var ranges: [Range<AttributedString.Index>] = []
    var start = text.startIndex
    var cursor = text.startIndex

    while cursor < text.endIndex {
        if text.characters[cursor].isNewline {
            ranges.append(start..<cursor)
            start = text.index(afterCharacter: cursor)
            cursor = start
        } else {
            cursor = text.index(afterCharacter: cursor)
        }
    }

    if start <= text.endIndex {
        ranges.append(start..<text.endIndex)
    }

    return ranges
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func appendTypedText(_ string: String, to viewModel: NativeNoteEditorViewModel) {
    var inserted = AttributedString(string)
    let range = inserted.startIndex..<inserted.endIndex
    inserted[range].mergeAttributes(
        viewModel.selection.typingAttributes(in: viewModel.attributedContent)
    )
    let insertion = viewModel.attributedContent.endIndex
    viewModel.attributedContent.insert(inserted, at: insertion)
    let cursor = viewModel.attributedContent.endIndex
    viewModel.selection = AttributedTextSelection(range: cursor..<cursor)
}

@available(iOS 26.0, macOS 26.0, *)
private func bridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(run.attributes)
    let bridged = NSAttributedString(sample)
    return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
}
