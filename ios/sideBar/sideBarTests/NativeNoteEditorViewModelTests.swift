import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesSelectedRangeFontTraits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Title\nhello"),
            plainText: "Title\nhello"
        )
        let start = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let end = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        let range = start..<end
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: range))

        let updatedStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let updatedEnd = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: updatedStart..<updatedEnd)
        viewModel.applyFormatting(.bold)
        let updatedRange = updatedStart..<updatedEnd
        XCTAssertFalse(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }

    func testApplyFormattingItalicTogglesSelectedRangeFontTraits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: range))

        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.italic)
        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertFalse(noteRangeHasItalicTrait(viewModel.attributedContent, range: updatedRange))
    }

    func testApplyFormattingPreservesSelectionAfterSelectedRangeMutation() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello world")
        let start = viewModel.attributedContent.index(viewModel.attributedContent.startIndex, offsetByCharacters: 6)
        let end = viewModel.attributedContent.index(start, offsetByCharacters: 5)
        let selectedRange = start..<end
        viewModel.selection = AttributedTextSelection(range: selectedRange)

        viewModel.applyFormatting(.underline)

        guard case .ranges(let ranges) = viewModel.selection.indices(in: viewModel.attributedContent) else {
            return XCTFail("Expected a selected range")
        }
        XCTAssertEqual(ranges.ranges.first, selectedRange)
        XCTAssertTrue(noteRangeIsUnderlined(viewModel.attributedContent, range: selectedRange))
    }

    func testApplyFormattingPreservesCodeBlockPresentationIntentOnSelectedRange() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let start = viewModel.index(forCharacterOffset: 8, in: viewModel.attributedContent)
        let end = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: start..<end)

        viewModel.applyFormatting(.bold)

        let intent = try XCTUnwrap(
            notePresentationIntent(in: viewModel.attributedContent, atCharacterOffset: 8)
        )
        XCTAssertEqual(intent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

#if os(macOS)
    func testApplyFormattingDoesNotMirrorPlatformFontTraitsIntoLiveDocument() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)
        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)

        XCTAssertFalse(noteRangeHasBridgedBoldPlatformFont(viewModel.attributedContent, range: updatedRange))
    }
#endif

    func testApplyFormattingBoldTogglesTypingAttributesAtInsertionPoint() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.bold)
        XCTAssertTrue(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).bold)

        viewModel.applyFormatting(.bold)
        XCTAssertFalse(noteTypingTraits(from: viewModel.selection.typingAttributes(in: viewModel.attributedContent)).bold)
    }

    func testEmptyTrailingParagraphAfterHeadingUsesPlainBodyTypingState() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        let typingAttributes = viewModel.typingAttributesForInsertion(in: viewModel.attributedContent)

        XCTAssertFalse(viewModel.isBoldActive())
        XCTAssertEqual(NoteTextBlockAttribute.blockType(from: typingAttributes.noteBlock), .paragraph)
        XCTAssertFalse(noteTypingTraits(from: typingAttributes).bold)
    }

    func testEmptyTrailingParagraphWithMissingBlockMarkerStillUsesPlainBodyTypingState() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .paragraph([.init(text: "", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let newlineStart = viewModel.index(forCharacterOffset: 13, in: viewModel.attributedContent)
        let newlineEnd = viewModel.attributedContent.endIndex
        viewModel.attributedContent[newlineStart..<newlineEnd].noteBlock = nil
        viewModel.attributedContent[newlineStart..<newlineEnd].noteStructuralBoundary = nil
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        let typingAttributes = viewModel.typingAttributesForInsertion(in: viewModel.attributedContent)

        XCTAssertFalse(viewModel.isBoldActive())
        XCTAssertEqual(NoteTextBlockAttribute.blockType(from: typingAttributes.noteBlock), .paragraph)
        XCTAssertFalse(noteTypingTraits(from: typingAttributes).bold)
    }

    func testPersistenceSnapshotRoundTripsAllowedInlineFormattingWithoutLoss() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Hello")
        let boldRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: boldRange)

        viewModel.applyFormatting(.bold)

        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        viewModel.applyFormatting(.underline)
        noteAppendTypedText("!", to: viewModel)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(
            canonicalContent: snapshot.canonicalContent,
            plainText: snapshot.plainText
        )

        let reloadedBoldRange = noteCharacterRange(length: 5, in: reloaded.attributedContent)
        let punctuationStart = reloaded.attributedContent.index(
            reloaded.attributedContent.startIndex,
            offsetByCharacters: 5
        )
        let punctuationEnd = reloaded.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertEqual(snapshot.plainText, "Hello!")
        XCTAssertTrue(noteRangeHasBoldTrait(reloaded.attributedContent, range: reloadedBoldRange))
        XCTAssertTrue(
            noteRangeIsUnderlined(
                reloaded.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
    }

    func testInsertionPointFormattingStatePersistsAcrossTypedTextEdits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Hi")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.applyFormatting(.italic)
        noteAppendTypedText("!", to: viewModel)

        let punctuationStart = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 2
        )
        let punctuationEnd = viewModel.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertTrue(viewModel.isItalicActive())
        XCTAssertTrue(
            noteRangeHasItalicTrait(
                viewModel.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
    }

    func testTypingAttributesInsideCodeBlockPreservePresentationIntentForInsertedText() async throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        let typingAttributes = viewModel.typingAttributesForInsertion(in: viewModel.attributedContent)
        let typingIntent = try XCTUnwrap(
            typingAttributes[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        )

        XCTAssertEqual(typingIntent.components.map(\.kind), [.codeBlock(languageHint: nil)])

        noteAppendTypedText("!", to: viewModel)

        let insertedIntent = try XCTUnwrap(
            notePresentationIntent(in: viewModel.attributedContent, atCharacterOffset: 16)
        )
        XCTAssertEqual(insertedIntent.components.map(\.kind), [.codeBlock(languageHint: nil)])
    }

    func testFormattingCommandsUpdateCanonicalSnapshotWithoutWrapperOwnedState() async throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Title\nHello"),
            plainText: "Title\nHello"
        )

        let start = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let end = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        let range = start..<end
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)

        let updatedStart = viewModel.index(forCharacterOffset: 6, in: viewModel.attributedContent)
        let updatedEnd = viewModel.index(forCharacterOffset: 11, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(
            range: updatedStart..<updatedEnd
        )
        viewModel.applyFormatting(.italic)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let paragraph = try XCTUnwrap(snapshot.document.blocks.last)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertEqual(segment.text, "Hello")
        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(segment.marks.contains(.italic))
        XCTAssertEqual(snapshot.plainText, "Title\nHello")
    }

    func testSelectedRangeFormattingStateUpdatesIndividuallyPerControl() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Title\nhello")
        func bodyRange() -> Range<AttributedString.Index> {
            let lowerBound = viewModel.attributedContent.index(
                viewModel.attributedContent.startIndex,
                offsetByCharacters: 6
            )
            return lowerBound..<viewModel.attributedContent.endIndex
        }
        let range = bodyRange()
        viewModel.selection = AttributedTextSelection(range: range)

        XCTAssertFalse(viewModel.isFormattingActive(.bold))
        viewModel.applyFormatting(.bold)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertFalse(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(
            range: bodyRange()
        )
        viewModel.applyFormatting(.italic)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(
            range: bodyRange()
        )
        viewModel.applyFormatting(.underline)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertTrue(viewModel.isFormattingActive(.underline))
    }

    func testInsertionPointFormattingStateUpdatesIndividuallyPerControlAndTypedText() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Title\nHi")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertFalse(viewModel.isFormattingActive(.bold))
        viewModel.applyFormatting(.bold)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertFalse(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.applyFormatting(.underline)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertTrue(viewModel.isFormattingActive(.underline))

        noteAppendTypedText("!", to: viewModel)

        let punctuationStart = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 8
        )
        let punctuationEnd = viewModel.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
        XCTAssertTrue(noteRangeIsUnderlined(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.minimumAutosaveDelay = 0
        viewModel.autosaveDelay = 0.01
        viewModel.loadText("hello")
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: previous)

        try? await waitUntil(timeoutSeconds: 0.2) {
            viewModel.hasUnsavedChanges && viewModel.autosaveToken > 0
        }
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertGreaterThan(viewModel.autosaveToken, 0)

        viewModel.markSaved(plainText: viewModel.currentPlainText())
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testSelectionLineSpanCoversInsertionAndMultiLineRanges() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.attributedContent = AttributedString("line1\nline2\nline3")

        let line2Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 6
        )
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...1)

        let line3Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 12
        )
        let line3Next = viewModel.attributedContent.index(afterCharacter: line3Start)
        viewModel.selection = AttributedTextSelection(range: line2Start..<line3Next)
        XCTAssertEqual(viewModel.selectionLineSpan(in: viewModel.attributedContent), 1...2)
    }

    func testHandleSelectionChangeTracksSpanTransitions() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.attributedContent = AttributedString("line1\nline2")

        let line1Start = viewModel.attributedContent.startIndex
        viewModel.selection = AttributedTextSelection(range: line1Start..<line1Start)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 0...0)

        let line1Next = viewModel.attributedContent.index(afterCharacter: line1Start)
        viewModel.selection = AttributedTextSelection(range: line1Next..<line1Next)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 0...0)

        let line2Start = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 6
        )
        viewModel.selection = AttributedTextSelection(range: line2Start..<line2Start)
        viewModel.handleSelectionChange()
        XCTAssertEqual(viewModel.lastSelectionLineSpan, 1...1)
    }

    func testSetInsertionPointPlacesSelectionFromCharacterOffsetAndClampsBounds() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Hello world")

        viewModel.setInsertionPoint(characterOffset: 5)
        assertInsertionPoint(
            viewModel.selectionSnapshot(in: viewModel.attributedContent),
            equals: 5
        )

        viewModel.setInsertionPoint(characterOffset: -3)
        assertInsertionPoint(
            viewModel.selectionSnapshot(in: viewModel.attributedContent),
            equals: 0
        )

        viewModel.setInsertionPoint(characterOffset: 999)
        assertInsertionPoint(
            viewModel.selectionSnapshot(in: viewModel.attributedContent),
            equals: 11
        )
    }

    func testSetInsertionPointUsesUTF16OffsetsForComposedEmoji() async {
        let viewModel = NativeNoteEditorViewModel()
        let text = "A👍🏽B"
        viewModel.loadText(text)

        viewModel.setInsertionPoint(characterOffset: 5)

        assertInsertionPoint(
            viewModel.selectionSnapshot(in: viewModel.attributedContent),
            equals: 2
        )
        assertInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 5
        )
    }

    func testHandleContentChangeMarksUnsavedImmediately() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 2.0
        viewModel.loadText("hello")

        let previous = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.autosaveToken, 0)
    }

    func testScheduleAutosaveCancelsSupersededTask() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.minimumAutosaveDelay = 0
        viewModel.autosaveDelay = 0.05
        viewModel.loadText("hello")

        let initial = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello1")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: initial)

        let secondPrevious = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello2")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: secondPrevious)

        try? await waitUntil(timeoutSeconds: 0.25) {
            viewModel.autosaveToken == 1
        }

        XCTAssertEqual(viewModel.autosaveToken, 1)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func notePresentationIntent(
    in text: AttributedString,
    atCharacterOffset offset: Int
) -> PresentationIntent? {
    guard offset >= 0, offset < text.characters.count else { return nil }
    let lower = text.index(text.startIndex, offsetByCharacters: offset)
    let upper = text.index(afterCharacter: lower)
    return text[lower..<upper]
        .runs
        .first?
        .attributes[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
}

@available(iOS 26.0, macOS 26.0, *)
private func assertInsertionPoint(
    _ snapshot: NativeNoteEditorViewModel.SelectionSnapshot,
    equals expectedOffset: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .insertionPoint(let offset) = snapshot else {
        return XCTFail("Expected insertion point selection", file: file, line: line)
    }
    XCTAssertEqual(offset, expectedOffset, file: file, line: line)
}

@available(iOS 26.0, macOS 26.0, *)
private func assertInsertionPointUTF16Offset(
    _ selection: AttributedTextSelection,
    in text: AttributedString,
    equals expectedOffset: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let characterOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: characterOffset)
        XCTAssertEqual(stringIndex.utf16Offset(in: string), expectedOffset, file: file, line: line)
    case .ranges:
        XCTFail("Expected insertion point selection", file: file, line: line)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async throws {
    let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
    let start = DispatchTime.now().uptimeNanoseconds

    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            XCTFail("Timed out waiting for condition")
            return
        }
        await Task.yield()
    }
}
