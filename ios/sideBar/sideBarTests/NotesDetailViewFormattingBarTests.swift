import Combine
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewFormattingBarTests: NotesDetailViewHostingTestCase {
    func testFormattingEntryControlUsesSharedActionButtonChrome() {
        XCTAssertEqual(NoteFormattingBarChrome.entryControlKind, .actionButton)
    }

#if os(iOS)
    func testCustomFormattingBarIsHiddenInReadModeOnIOS() async {
        let context = await makeNotesDetailViewTestContext()

        XCTAssertFalse(context.makeView().isCustomFormattingBarVisible)
    }

    func testFloatingFormattingBarHostIsHiddenInReadMode() async {
        let context = await makeNotesDetailViewTestContext()

        XCTAssertEqual(context.makeView().formattingBarPresentation, .hidden)
        XCTAssertFalse(context.makeView().isFloatingFormattingBarVisible)
    }

    func testFormattingBarPresentationUsesFloatingTopTrailingOnIPadInEditMode() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: false,
                isSoftwareKeyboardVisible: false
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesFloatingTopTrailingWhenSoftwareKeyboardIsHidden() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: false
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesFloatingTopTrailingOnIPhoneBeforeSoftwareKeyboardIsVisible() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: false
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesKeyboardAccessoryWhenSoftwareKeyboardIsVisible() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: true
            ),
            .keyboardAccessory
        )
    }

    func testFormattingBarPresentationIsHiddenInReadMode() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: false,
                isPhone: true,
                isSoftwareKeyboardVisible: false
            ),
            .hidden
        )
    }

    func testFormattingBarPresentationDefaultsToVisibleEditingPresentationBeforeBoundarySignalArrives() async {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        XCTAssertEqual(
            context.makeView().formattingBarPresentation,
            .floatingTopTrailing
        )
        XCTAssertTrue(context.makeView().isFormattingToolbarVisible)
    }

    @available(iOS 26.0, *)
    func testFloatingFormattingBarRendersTopTrailingInEditMode() async throws {
        let controller = mount(
            FloatingFormattingBarHost(
                configuration: .disabled
            )
        )
        let barView = try XCTUnwrap(
            findDescendantView(
                in: controller.view,
                accessibilityIdentifier: "note-formatting-bar"
            )
        )
        let barFrame = barView.convert(barView.bounds, to: controller.view)
        let rootBounds = controller.view.bounds

        XCTAssertLessThan(barFrame.width, 240)
        XCTAssertGreaterThan(barFrame.minX, rootBounds.midX)
        XCTAssertEqual(
            barFrame.maxX,
            rootBounds.maxX - DesignTokens.Spacing.md,
            accuracy: 0.5
        )
    }

    @available(iOS 26.0, *)
    func testFloatingFormattingBarStaysHiddenInReadModeEvenWhenFloatingPresentationIsOverridden() async {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let view = NotesDetailView(
            viewModel: context.notesViewModel,
            editorViewModel: context.editorViewModel,
            isMoveSheetPresented: .constant(false),
            moveSelection: .constant(""),
            isRenameAlertPresented: .constant(false),
            renameValue: .constant(""),
            isDeleteAlertPresented: .constant(false),
            isExporting: .constant(false),
            exportDocument: .constant(nil),
            exportFilename: .constant(""),
            formattingBarPresentationOverride: .floatingTopTrailing
        )

        XCTAssertEqual(context.makeView().formattingBarPresentation, .hidden)
        XCTAssertFalse(view.isFloatingFormattingBarVisible)
        XCTAssertFalse(view.isFormattingToolbarVisible)
    }

    func testFormattingBarConfigurationTapUpdatesCanonicalSnapshotAndSelectedState() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Title\nHello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let selectionStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let selectionEnd = nativeViewModel.index(forCharacterOffset: 11, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(
            range: selectionStart..<selectionEnd
        )
        let configuration = context.makeView().noteFormattingBarConfiguration

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertFalse(configuration.isBoldActive)

        configuration.onBoldTap()

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        let paragraph = try XCTUnwrap(document.blocks.dropFirst().first)
        let segment = try XCTUnwrap(paragraph.content.first)

        XCTAssertTrue(segment.marks.contains(.bold))
        XCTAssertTrue(
            noteRangeHasBoldTrait(
                nativeViewModel.attributedContent,
                range: {
                    let lower = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
                    let upper = nativeViewModel.index(forCharacterOffset: 11, in: nativeViewModel.attributedContent)
                    return lower..<upper
                }()
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
        await waitUntil(timeout: .seconds(1)) {
            changeCount > 0
        }

        XCTAssertGreaterThan(changeCount, 0)
    }

    func testEditorViewModelPublishesWhenNativeSelectionChanges() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        await Task.yield()

        let expectation = expectation(description: "editor objectWillChange")
        var observedSelectionOffsets: [Int] = []
        let cancellable = context.editorViewModel.objectWillChange.sink {
            observedSelectionOffsets.append(
                nativeViewModel.selectionStartCharacterOffset(in: nativeViewModel.attributedContent)
            )
            expectation.fulfill()
        }
        defer { cancellable.cancel() }

        let target = nativeViewModel.index(forCharacterOffset: 5, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: target..<target)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(observedSelectionOffsets, [5])
    }

    func testFormattingBarConfigurationAppliesTextStyleSelectionToCurrentBlock() async throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Requires iOS 26")
        }

        let note = NotePayload(
            id: "n1",
            name: "Title",
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "Body", marks: [.bold])])
                ]
            ),
            plainText: "Title\nBody",
            path: "/note.md",
            modified: nil,
            created: nil
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let bodyStart = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        let bodyEnd = nativeViewModel.index(forCharacterOffset: 10, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: bodyStart..<bodyEnd)
        nativeViewModel.handleSelectionChange()

        let configuration = context.makeView().noteFormattingBarConfiguration
        XCTAssertEqual(configuration.activeTextStyle, .body)

        configuration.selectTextStyle(.heading)

        let document = context.editorViewModel.currentSemanticDocumentSnapshot()
        XCTAssertEqual(document.blocks.map(\.type), [.title, .heading])
        XCTAssertEqual(context.makeView().noteFormattingBarConfiguration.activeTextStyle, .heading)
        XCTAssertEqual(document.blocks[1].content.first?.marks, [.bold])
    }

#elseif os(macOS)
    func testCustomFormattingBarIsVisibleOnMacOSInEditMode() async throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Requires macOS 26")
        }

        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()

        XCTAssertTrue(context.makeView().isCustomFormattingBarVisible)
    }

    func testFloatingFormattingBarHostMountsFormattingButtonOnMacOS() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Requires macOS 26")
        }

        let controller = mount(
            FloatingFormattingBarHost(
                configuration: .disabled
            )
        )
        let barView = try XCTUnwrap(
            findDescendantView(
                in: controller.view,
                identifier: "note-formatting-bar"
            )
        )
        let buttonView = try XCTUnwrap(
            findDescendantView(
                in: controller.view,
                identifier: "note-formatting-menu"
            )
        )

        XCTAssertGreaterThan(barView.bounds.width, 0)
        XCTAssertGreaterThan(buttonView.bounds.width, 0)
    }
#endif
}

#if os(iOS)
@MainActor
@available(iOS 26.0, *)
private struct FloatingFormattingBarHost: View {
    let configuration: NoteFormattingBarConfiguration

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                UIKitNoteFormattingBarRepresentable(
                    configuration: configuration
                )
                .fixedSize()
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.trailing, DesignTokens.Spacing.md)
            }
    }
}

@MainActor
private func findDescendantView(in view: UIView, accessibilityIdentifier: String) -> UIView? {
    if view.accessibilityIdentifier == accessibilityIdentifier {
        return view
    }

    for subview in view.subviews {
        if let match = findDescendantView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }

    return nil
}
#elseif os(macOS)
@MainActor
@available(macOS 26.0, *)
private struct FloatingFormattingBarHost: View {
    let configuration: NoteFormattingBarConfiguration

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                AppKitNoteFormattingOverlay(
                    configuration: configuration,
                    presentation: .floatingTopTrailing
                )
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.trailing, DesignTokens.Spacing.md)
            }
    }
}

@MainActor
private func findDescendantView(in view: NSView, identifier: String) -> NSView? {
    if view.identifier?.rawValue == identifier {
        return view
    }

    for subview in view.subviews {
        if let match = findDescendantView(in: subview, identifier: identifier) {
            return match
        }
    }

    return nil
}
#endif
