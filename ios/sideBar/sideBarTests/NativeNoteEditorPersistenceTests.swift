import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorPersistenceTests: XCTestCase {
    func testCurrentPersistenceSnapshotExportsPlainTextAndSemanticCanonicalDocument() async throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.plainText, "hello")
        XCTAssertFalse(snapshot.canonicalContent.isEmpty)
        let canonicalDocument = try XCTUnwrap(NotesSemanticDocumentCodec.decode(snapshot.canonicalContent))
        XCTAssertEqual(canonicalDocument, snapshot.document)
        XCTAssertEqual(NotesSemanticDocumentProjection.plainText(from: canonicalDocument), "hello")
    }

    func testLoadTextEmptySeedsSingleTitleBlock() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let snapshot = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(
            snapshot.document.blocks,
            [.init(type: .title, content: [.init(text: "", marks: [])])]
        )
        XCTAssertEqual(snapshot.plainText, "")
    }

    func testTypingReturnFromTitleCreatesParagraphBodyBlock() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Title")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        noteAppendTypedText("\nBody", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(
            snapshot.document.blocks,
            [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        XCTAssertEqual(snapshot.plainText, "Title\nBody")
    }

    func testCurrentPersistenceSnapshotNormalizesBlockZeroToTitle() async throws {
        let encoded = try XCTUnwrap(
            NotesSemanticDocumentCodec.encode(
                NotesSemanticDocument(
                    blocks: [
                        .init(type: .heading, content: [.init(text: "Heading first", marks: [])]),
                        .paragraph([.init(text: "Body", marks: [])])
                    ]
                )
            )
        )
        let viewModel = NativeNoteEditorViewModel()

        viewModel.loadDocument(canonicalContent: encoded, plainText: "Heading first\nBody")

        let snapshot = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(
            snapshot.document.blocks,
            [
                .init(type: .title, content: [.init(text: "Heading first", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        XCTAssertEqual(snapshot.plainText, "Heading first\nBody")
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

        let fullRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.bold)

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasBoldTrait(reloaded.attributedContent, range: reloadedRange))
    }

    func testPersistenceSnapshotRoundTripPreservesItalicFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.italic)

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasItalicTrait(reloaded.attributedContent, range: reloadedRange))
    }

    func testPersistenceSnapshotRoundTripPreservesUnderlineFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.underline)

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeIsUnderlined(reloaded.attributedContent, range: reloadedRange))
    }

    func testLoadDocumentPreservesExternallyEncodedBoldFormatting() async throws {
        let encoded = try XCTUnwrap(
            NotesSemanticDocumentCodec.encode(
                NotesSemanticDocument(
                    blocks: [
                        .paragraph([.init(text: "Bold", marks: [.bold])])
                    ]
                )
            )
        )

        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(canonicalContent: encoded, plainText: "Bold")
        let range = noteCharacterRange(length: 4, in: viewModel.attributedContent)

        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: range))
    }

    func testLoadDocumentPreservesExternallyEncodedItalicFormatting() async throws {
        let encoded = try XCTUnwrap(
            NotesSemanticDocumentCodec.encode(
                NotesSemanticDocument(
                    blocks: [
                        .paragraph([.init(text: "Italic", marks: [.italic])])
                    ]
                )
            )
        )

        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(canonicalContent: encoded, plainText: "Italic")
        let range = noteCharacterRange(length: 6, in: viewModel.attributedContent)

        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripPreservesSwiftUIFontOnlyBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.attributedContent[fullRange].font = .system(size: 16, weight: .bold)
        #if os(iOS)
        viewModel.attributedContent[fullRange][AttributeScopes.UIKitAttributes.FontAttribute.self] = nil
        #endif

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasBoldTrait(reloaded.attributedContent, range: reloadedRange))
    }

    func testPersistenceSnapshotRoundTripPreservesSwiftUIFontOnlyItalicFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.attributedContent[fullRange].font = .system(size: 16).italic()
        #if os(iOS)
        viewModel.attributedContent[fullRange][AttributeScopes.UIKitAttributes.FontAttribute.self] = nil
        #endif

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasItalicTrait(reloaded.attributedContent, range: reloadedRange))
    }

    func testPersistenceSnapshotRoundTripPreservesInsertionPointTypingFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        viewModel.applyFormatting(.bold)
        viewModel.applyFormatting(.italic)
        viewModel.applyFormatting(.underline)
        noteAppendTypedText("A", to: viewModel)

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let firstRun = reloaded.attributedContent.runs.first

        XCTAssertNotNil(firstRun)
        XCTAssertTrue(firstRun.map(noteRunHasBoldTrait) == true)
        XCTAssertTrue(firstRun.map(noteRunHasItalicTrait) == true)
        XCTAssertEqual(firstRun?.underlineStyle, .single)
    }

    func testPersistenceSnapshotRoundTripRemovesBoldFormattingWhenToggledOff() async {
        let reloaded = roundTripAfterToggleOff(.bold)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertFalse(noteRangeHasBoldTrait(reloaded.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripRemovesItalicFormattingWhenToggledOff() async {
        let reloaded = roundTripAfterToggleOff(.italic)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertFalse(noteRangeHasItalicTrait(reloaded.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripRemovesUnderlineFormattingWhenToggledOff() async {
        let reloaded = roundTripAfterToggleOff(.underline)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertFalse(noteRangeIsUnderlined(reloaded.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripPreservesBoldFormattingAfterSameSelectionToggleOnOffOn() async {
        let reloaded = roundTripAfterToggleOnOffOn(.bold)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasBoldTrait(reloaded.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripPreservesItalicFormattingAfterSameSelectionToggleOnOffOn() async {
        let reloaded = roundTripAfterToggleOnOffOn(.italic)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeHasItalicTrait(reloaded.attributedContent, range: range))
    }

    func testPersistenceSnapshotRoundTripPreservesUnderlineFormattingAfterSameSelectionToggleOnOffOn() async {
        let reloaded = roundTripAfterToggleOnOffOn(.underline)
        let range = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertTrue(noteRangeIsUnderlined(reloaded.attributedContent, range: range))
    }

    func testLoadTextEmptySeedsBodyTypingAttributes() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("")

        let attrs = viewModel.defaultTypingAttributes()
        let traits = noteTypingTraits(from: attrs)
        XCTAssertFalse(traits.bold)
        XCTAssertFalse(traits.italic)
        XCTAssertNotNil(attrs.paragraphStyle)
        XCTAssertNotNil(attrs.font)
    }

    func testLoadDocumentNormalizesToCurrentBaseFontSize() async {
        let source = NativeNoteEditorViewModel()
        source.setBaseFontSize(14)
        source.loadText("hello")
        let range = noteCharacterRange(length: 5, in: source.attributedContent)
        source.selection = AttributedTextSelection(range: range)
        source.applyFormatting(.bold)
        let snapshot = source.currentPersistenceSnapshot()

        let reloaded = NativeNoteEditorViewModel()
        reloaded.setBaseFontSize(22)
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        var expectedContent = NotesAttributedDocumentCodec.attributedString(
            from: snapshot.document,
            baseFontSize: 22
        )
        NoteTextFormattingDefinition(baseFontSize: 22).constrainDocument(&expectedContent)

        XCTAssertEqual(reloaded.attributedContent, expectedContent)
        XCTAssertTrue(
            noteRangeHasBoldTrait(
                reloaded.attributedContent,
                range: noteCharacterRange(length: 5, in: reloaded.attributedContent)
            )
        )
    }

    func testLoadTextDoesNotInferMarkdownStructureFromLiteralPrefixes() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("# Heading\n- bullet\n> quote")

        let plainText = String(viewModel.attributedContent.characters)
        XCTAssertEqual(plainText, "# Heading\n- bullet\n> quote")
        XCTAssertFalse(viewModel.attributedContent.runs.contains { run in
            run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] != nil
        })
    }

    func testCurrentPersistenceSnapshotIsIdempotentAcrossRepeatedCalls() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)
        viewModel.applyFormatting(.underline)

        let first = viewModel.currentPersistenceSnapshot()
        let second = viewModel.currentPersistenceSnapshot()

        XCTAssertEqual(first.document, second.document)
        XCTAssertEqual(first.plainText, second.plainText)
        XCTAssertEqual(first.canonicalContent, second.canonicalContent)
    }

#if os(macOS)
    func testPersistenceRoundTripDoesNotMirrorPlatformFontTraitsIntoLiveDocument() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)

        let reloaded = reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
        let reloadedRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)

        XCTAssertFalse(noteRangeHasBridgedBoldPlatformFont(reloaded.attributedContent, range: reloadedRange))
    }
#endif
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func roundTripAfterToggleOff(_ formatting: NoteFormatting) -> NativeNoteEditorViewModel {
    let viewModel = NativeNoteEditorViewModel()
    viewModel.loadText("hello")
    let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
    viewModel.selection = AttributedTextSelection(range: range)
    viewModel.applyFormatting(formatting)
    viewModel.selection = AttributedTextSelection(
        range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
    )
    viewModel.applyFormatting(formatting)
    return reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func roundTripAfterToggleOnOffOn(_ formatting: NoteFormatting) -> NativeNoteEditorViewModel {
    let viewModel = NativeNoteEditorViewModel()
    viewModel.loadText("hello")
    let initialRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
    viewModel.selection = AttributedTextSelection(range: initialRange)
    viewModel.applyFormatting(formatting)
    viewModel.selection = AttributedTextSelection(
        range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
    )
    viewModel.applyFormatting(formatting)
    viewModel.selection = AttributedTextSelection(
        range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
    )
    viewModel.applyFormatting(formatting)
    return reloadedViewModel(from: viewModel.currentPersistenceSnapshot())
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func reloadedViewModel(
    from snapshot: NativeNoteEditorViewModel.PersistenceSnapshot
) -> NativeNoteEditorViewModel {
    let reloaded = NativeNoteEditorViewModel()
    reloaded.loadDocument(
        canonicalContent: snapshot.canonicalContent,
        plainText: snapshot.plainText
    )
    return reloaded
}
