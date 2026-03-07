import Combine
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewFormattingBarTests: XCTestCase {
#if os(iOS)
    func testCustomFormattingBarIsHiddenInReadModeOnIOS() async {
        let context = await makeNotesDetailViewTestContext()

        XCTAssertFalse(context.makeView().isCustomFormattingBarVisible)
    }

    func testMobileFormattingBarPlacementUsesKeyboardAccessoryOnPhoneInEditMode() {
        XCTAssertEqual(
            NotesDetailView.mobileFormattingBarPlacement(isEditing: true, isPhone: true),
            .keyboardAccessory
        )
    }

    func testMobileFormattingBarPlacementUsesTopAttachedBarOnIPadInEditMode() {
        XCTAssertEqual(
            NotesDetailView.mobileFormattingBarPlacement(isEditing: true, isPhone: false),
            .topAttached
        )
    }

    func testMobileFormattingBarPlacementHidesBarInReadMode() {
        XCTAssertEqual(
            NotesDetailView.mobileFormattingBarPlacement(isEditing: false, isPhone: true),
            .hidden
        )
    }

    func testFormattingBarConfigurationTapUpdatesCanonicalSnapshotAndSelectedState() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        nativeViewModel.selection = AttributedTextSelection(
            range: noteCharacterRange(length: 5, in: nativeViewModel.attributedContent)
        )
        let configuration = context.makeView().noteFormattingBarConfiguration

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertFalse(configuration.isBoldActive)

        configuration.onBoldTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        let paragraph = try XCTUnwrap(document.blocks.first)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(
            noteRangeHasBoldTrait(
                nativeViewModel.attributedContent,
                range: noteCharacterRange(length: 5, in: nativeViewModel.attributedContent)
            )
        )
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isBoldActive)
    }

    func testFormattingBarConfigurationInsertionPointToggleFormatsTypedTextAndUpdatesState() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hi"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let insertion = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        let configuration = context.makeView().noteFormattingBarConfiguration

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertFalse(configuration.isUnderlineActive)

        configuration.onUnderlineTap()
        noteAppendTypedText("!", to: nativeViewModel)

        let punctuationStart = nativeViewModel.attributedContent.index(
            nativeViewModel.attributedContent.startIndex,
            offsetByCharacters: 2
        )
        let punctuationEnd = nativeViewModel.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertTrue(
            noteRangeIsUnderlined(
                nativeViewModel.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
        XCTAssertTrue(context.editorViewModel.isFormattingActive(.underline))
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isUnderlineActive)
    }

    func testFormattingBarConfigurationBecomesEnabledAfterEditorAttaches() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isEnabled)

        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)

        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isEnabled)
    }

    func testFormattingBarConfigurationReflectsSelectionChangesFromNativeEditor() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " plain", marks: [])
                ])
            ]
        )
        let note = NotePayload(
            id: "n1",
            name: "Selection State",
            document: document,
            plainText: "Bold plain",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let plainStart = nativeViewModel.attributedContent.index(
            nativeViewModel.attributedContent.startIndex,
            offsetByCharacters: 5
        )
        let plainEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: plainStart..<plainEnd)
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isBoldActive)

        let boldRange = noteCharacterRange(length: 4, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: boldRange)
        nativeViewModel.handleSelectionChange()

        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isBoldActive)
    }

    func testEditorViewModelPublishesWhenNativeEditorAttaches() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        var changeCount = 0
        let cancellable = context.editorViewModel.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        context.editorViewModel.attachNativeEditor(context.editorViewModel.makeNativeEditorViewModel())

        XCTAssertGreaterThan(changeCount, 0)
    }

    func testEditorViewModelPublishesWhenNativeSelectionChanges() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        var changeCount = 0
        let cancellable = context.editorViewModel.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        let range = noteCharacterRange(length: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: range)
        nativeViewModel.handleSelectionChange()

        XCTAssertGreaterThan(changeCount, 0)
    }
#elseif os(macOS)
    func testCustomFormattingBarRemainsHiddenOnMacOS() async throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Requires macOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        XCTAssertFalse(context.makeView().isCustomFormattingBarVisible)
    }
#endif
}
