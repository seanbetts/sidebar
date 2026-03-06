import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorViewModelTests: XCTestCase {
    func testApplyFormattingBoldTogglesSelectedRangeFontTraits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.bold)
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: range))
#if os(macOS)
        XCTAssertTrue(noteRangeHasBridgedBoldPlatformFont(viewModel.attributedContent, range: range))
#endif

        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.bold)
        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertFalse(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
#if os(macOS)
        XCTAssertFalse(noteRangeHasBridgedBoldPlatformFont(viewModel.attributedContent, range: updatedRange))
#endif
    }

    func testApplyFormattingItalicTogglesSelectedRangeFontTraits() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: range))
#if os(macOS)
        XCTAssertTrue(noteRangeHasBridgedItalicPlatformFont(viewModel.attributedContent, range: range))
#endif

        viewModel.selection = AttributedTextSelection(range: noteCharacterRange(length: 5, in: viewModel.attributedContent))
        viewModel.applyFormatting(.italic)
        let updatedRange = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        XCTAssertFalse(noteRangeHasItalicTrait(viewModel.attributedContent, range: updatedRange))
#if os(macOS)
        XCTAssertFalse(noteRangeHasBridgedItalicPlatformFont(viewModel.attributedContent, range: updatedRange))
#endif
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

    func testFormattingCommandsUpdateCanonicalSnapshotWithoutWrapperOwnedState() async throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Hello")

        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)

        viewModel.selection = AttributedTextSelection(
            range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
        )
        viewModel.applyFormatting(.italic)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let paragraph = try XCTUnwrap(snapshot.document.blocks.first)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertEqual(segment.text, "Hello")
        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(segment.marks.contains(.italic))
        XCTAssertEqual(snapshot.plainText, "Hello")
    }

    func testSelectedRangeFormattingStateUpdatesIndividuallyPerControl() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let range = noteCharacterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)

        XCTAssertFalse(viewModel.isFormattingActive(.bold))
        viewModel.applyFormatting(.bold)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertFalse(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(
            range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
        )
        viewModel.applyFormatting(.italic)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(
            range: noteCharacterRange(length: 5, in: viewModel.attributedContent)
        )
        viewModel.applyFormatting(.underline)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertTrue(viewModel.isFormattingActive(.underline))
    }

    func testInsertionPointFormattingStateUpdatesIndividuallyPerControlAndTypedText() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Hi")
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
            offsetByCharacters: 2
        )
        let punctuationEnd = viewModel.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
        XCTAssertTrue(noteRangeHasItalicTrait(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
        XCTAssertTrue(noteRangeIsUnderlined(viewModel.attributedContent, range: punctuationStart..<punctuationEnd))
    }

    func testHandleContentChangeSetsUnsavedStateAndMarkSavedClearsIt() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.autosaveDelay = 0.3
        viewModel.loadText("hello")
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello world")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: previous)

        for _ in 0..<20 {
            if viewModel.hasUnsavedChanges, viewModel.autosaveToken > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
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
        viewModel.autosaveDelay = 0.5
        viewModel.loadText("hello")

        let initial = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello1")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: initial)

        try? await Task.sleep(nanoseconds: 100_000_000)

        let secondPrevious = viewModel.attributedContent
        viewModel.attributedContent = AttributedString("hello2")
        viewModel.selection = AttributedTextSelection(
            range: viewModel.attributedContent.endIndex..<viewModel.attributedContent.endIndex
        )
        viewModel.handleContentChange(previous: secondPrevious)

        try? await Task.sleep(nanoseconds: 750_000_000)

        XCTAssertEqual(viewModel.autosaveToken, 1)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
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
