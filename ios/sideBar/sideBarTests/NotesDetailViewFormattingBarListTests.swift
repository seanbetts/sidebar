import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewFormattingBarListTests: NotesDetailViewHostingTestCase {
    func testFormattingBarConfigurationUnorderedListTapConvertsParagraphsIntoList() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])])
                ]
            ),
            plainText: "Title\nFirst\nSecond",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isUnorderedListEnabled)
        XCTAssertFalse(configuration.isUnorderedListActive)

        configuration.onUnorderedListTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .unorderedList])
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isUnorderedListActive)
    }

    func testFormattingBarConfigurationUnorderedListTapTogglesActiveListBackToParagraphs() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .unorderedList,
                        children: [
                            .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                            .init(type: .listItem, content: [.init(text: "Second", marks: [])])
                        ]
                    )
                ]
            ),
            plainText: "Title\n- First\n- Second",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isUnorderedListEnabled)
        XCTAssertTrue(configuration.isUnorderedListActive)

        configuration.onUnorderedListTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .paragraph, .paragraph])
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isUnorderedListActive)
    }

    func testFormattingBarConfigurationOrderedListTapConvertsParagraphsIntoList() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])])
                ]
            ),
            plainText: "Title\nFirst\nSecond",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isOrderedListEnabled)
        XCTAssertFalse(configuration.isOrderedListActive)

        configuration.onOrderedListTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .orderedList])
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isOrderedListActive)
    }

    func testFormattingBarConfigurationOrderedListTapTogglesActiveListBackToParagraphs() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .orderedList,
                        children: [
                            .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                            .init(type: .listItem, content: [.init(text: "Second", marks: [])])
                        ]
                    )
                ]
            ),
            plainText: "Title\n1. First\n2. Second",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isOrderedListEnabled)
        XCTAssertTrue(configuration.isOrderedListActive)

        configuration.onOrderedListTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .paragraph, .paragraph])
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isOrderedListActive)
    }

    func testFormattingBarConfigurationChecklistTapConvertsParagraphsIntoChecklist() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])])
                ]
            ),
            plainText: "Title\nFirst\nSecond",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isChecklistEnabled)
        XCTAssertFalse(configuration.isChecklistActive)

        configuration.onChecklistTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .checklist])
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isChecklistActive)
    }

    func testFormattingBarConfigurationBlockquoteTapConvertsParagraphsIntoBlockquote() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "First", marks: [])]),
                    .paragraph([.init(text: "Second", marks: [])])
                ]
            ),
            plainText: "Title\nFirst\nSecond",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isBlockquoteEnabled)
        XCTAssertFalse(configuration.isBlockquoteActive)

        configuration.onBlockquoteTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .blockquote])
        XCTAssertTrue(context.makeView().noteFormattingBarConfiguration.isBlockquoteActive)
    }

    func testFormattingBarConfigurationBlockquoteTapTogglesActiveBlockquoteBackToParagraphs() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26 or macOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(
                        type: .blockquote,
                        children: [
                            .paragraph([.init(text: "First", marks: [])]),
                            .paragraph([.init(text: "Second", marks: [])])
                        ]
                    )
                ]
            ),
            plainText: "Title\n> First\n> Second",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        _ = await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.currentNoteId == "n1"
        }
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()

        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: selectionStart..<selectionEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertTrue(configuration.isBlockquoteEnabled)
        XCTAssertTrue(configuration.isBlockquoteActive)

        configuration.onBlockquoteTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .paragraph, .paragraph])
        XCTAssertFalse(context.makeView().noteFormattingBarConfiguration.isBlockquoteActive)
    }
}
