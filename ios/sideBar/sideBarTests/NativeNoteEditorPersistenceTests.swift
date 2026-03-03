import XCTest
import SwiftUI
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
            guard let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldFont)
    }

    func testPersistenceSnapshotRoundTripPreservesBulletListFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("item")

        let first = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: first)
        viewModel.selection = AttributedTextSelection(range: first..<next)
        viewModel.applyFormatting(.bulletList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(snapshot.plainText.hasPrefix("• "))
        XCTAssertTrue(reloaded.currentPlainText().hasPrefix("• "))
    }

    func testLoadTextEmptySeedsParagraphTypingAttributes() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let attrs = viewModel.defaultTypingAttributes()
        XCTAssertEqual(attrs.blockKind, .paragraph)
        XCTAssertNotNil(attrs.paragraphStyle)
        #if os(iOS)
        XCTAssertNotNil(attrs[AttributeScopes.UIKitAttributes.FontAttribute.self])
        #elseif os(macOS)
        XCTAssertNotNil(attrs[AttributeScopes.AppKitAttributes.FontAttribute.self])
        #endif
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

    func testPlainTextRuntimeModeIgnoresFormattingCommands() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.setPlainTextRuntimeModeEnabled(true)

        let before = viewModel.attributedContent
        viewModel.applyFormatting(.bold)

        XCTAssertEqual(viewModel.attributedContent, before)
        XCTAssertFalse(viewModel.isBoldActive())
    }

    func testPlainTextRuntimeModeFlattensInlineFormattingWhenLoadingDocument() async {
        let source = NativeNoteEditorViewModel()
        source.loadText("hello")
        let fullRange = characterRange(length: 5, in: source.attributedContent)
        source.selection = AttributedTextSelection(range: fullRange)
        source.applyFormatting(.bold)
        let snapshot = source.currentPersistenceSnapshot()

        let reloaded = NativeNoteEditorViewModel()
        reloaded.setPlainTextRuntimeModeEnabled(true)
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let hasBoldIntent = reloaded.attributedContent.runs.contains { run in
            (run.inlinePresentationIntent ?? []).contains(.stronglyEmphasized)
        }
        XCTAssertFalse(hasBoldIntent)
        let reloadedRange = characterRange(length: 5, in: reloaded.attributedContent)
        XCTAssertEqual(reloaded.attributedContent.blockKind(in: reloadedRange), .paragraph)
    }

    func testPlainTextRuntimeModeSnapshotEncodesPlainTextCanonical() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.bold)
        viewModel.setPlainTextRuntimeModeEnabled(true)

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.plainText, "hello")
        XCTAssertEqual(snapshot.canonicalContent, NotesRichTextCodec.encodePlainTextToBase64RTF("hello"))
    }

    func testPlainTextRuntimeModeTypingAttributesUseZeroParagraphSpacing() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("line 1\n\nline 3")
        viewModel.setPlainTextRuntimeModeEnabled(true)

        let attrs = viewModel.defaultTypingAttributes()
        let style = attrs.paragraphStyle

        XCTAssertNotNil(style)
        XCTAssertEqual(style?.lineSpacing ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(style?.lineHeightMultiple ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(style?.minimumLineHeight ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(style?.maximumLineHeight ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(style?.paragraphSpacingBefore ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(style?.paragraphSpacing ?? -1, 0, accuracy: 0.001)
    }

    func testPlainTextRuntimeModeRoundTripKeepsZeroParagraphSpacingAcrossBlankLines() async {
        let source = NativeNoteEditorViewModel()
        source.loadText("line 1\n\nline 3")
        source.setPlainTextRuntimeModeEnabled(true)

        let snapshot = source.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.setPlainTextRuntimeModeEnabled(true)
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertEqual(reloaded.currentPlainText(), "line 1\n\nline 3")
        assertZeroParagraphSpacing(in: reloaded.attributedContent)
    }

    func testPlainTextRuntimeModeSkipsListMarkerPrefixRefreshPath() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Item")
        viewModel.setPlainTextRuntimeModeEnabled(true)

        let fullRange = characterRange(length: 4, in: viewModel.attributedContent)
        viewModel.attributedContent[fullRange].blockKind = .bulletList
        viewModel.attributedContent[fullRange].listDepth = 1
        let before = viewModel.attributedContent

        viewModel.requestPrefixRefresh(scope: .full)
        await Task.yield()
        viewModel.updatePrefixVisibility()

        XCTAssertEqual(String(viewModel.attributedContent.characters), "Item")
        XCTAssertEqual(viewModel.attributedContent, before)
        XCTAssertFalse(viewModel.attributedContent.runs.contains { $0.listMarker == true })
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
        if let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] {
            return font.pointSize
        }
        #elseif os(macOS)
        if let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] {
            return font.pointSize
        }
        #endif
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func assertZeroParagraphSpacing(
    in text: AttributedString,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for run in text.runs {
        guard let style = run.paragraphStyle else { continue }
        XCTAssertEqual(style.lineSpacing, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(style.lineHeightMultiple, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(style.minimumLineHeight, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(style.maximumLineHeight, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(style.paragraphSpacingBefore, 0, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(style.paragraphSpacing, 0, accuracy: 0.001, file: file, line: line)
    }
}
