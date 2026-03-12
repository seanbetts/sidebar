import Combine
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
final class NotesDetailViewFormattingBarTests: NotesDetailViewHostingTestCase {
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
                isSoftwareKeyboardVisible: false,
                isHardwareKeyboardInputExpected: false
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesFloatingTopTrailingWhenHardwareKeyboardInputIsExpected() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: false,
                isHardwareKeyboardInputExpected: true
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesFloatingTopTrailingOnIPhoneBeforeSoftwareKeyboardIsVisible() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: false,
                isHardwareKeyboardInputExpected: false
            ),
            .floatingTopTrailing
        )
    }

    func testFormattingBarPresentationUsesKeyboardAccessoryWhenSoftwareKeyboardIsVisible() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: true,
                isHardwareKeyboardInputExpected: false
            ),
            .keyboardAccessory
        )
    }

    func testFormattingBarPresentationPrefersKeyboardAccessoryWhenSoftwareKeyboardIsVisibleAndHardwareKeyboardInputIsExpected() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: true,
                isPhone: true,
                isSoftwareKeyboardVisible: true,
                isHardwareKeyboardInputExpected: true
            ),
            .keyboardAccessory
        )
    }

    func testFormattingBarPresentationIsHiddenInReadMode() {
        XCTAssertEqual(
            NoteFormattingBarPresentation.resolve(
                isEditing: false,
                isPhone: true,
                isSoftwareKeyboardVisible: false,
                isHardwareKeyboardInputExpected: false
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
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        context.editorViewModel.enterEditMode()
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            NotesDetailView(
                viewModel: context.notesViewModel,
                editorViewModel: context.editorViewModel,
                isMoveSheetPresented: .constant(false),
                moveSelection: .constant(""),
                isDeleteAlertPresented: .constant(false),
                isExporting: .constant(false),
                exportDocument: .constant(nil),
                exportFilename: .constant(""),
                formattingBarPresentationOverride: .floatingTopTrailing
            ),
            environment: environment
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
        XCTAssertGreaterThan(barFrame.maxX, rootBounds.maxX - 40)
    }

    @available(iOS 26.0, *)
    func testFloatingFormattingBarStaysHiddenInReadModeEvenWhenFloatingPresentationIsOverridden() async {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let view = NotesDetailView(
            viewModel: context.notesViewModel,
            editorViewModel: context.editorViewModel,
            isMoveSheetPresented: .constant(false),
            moveSelection: .constant(""),
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

    @available(iOS 26.0, *)
    func testAttributedNoteEditorContainerReevaluatesPresentationWhenInputModeChanges() async throws {
        let context = await makeNotesDetailViewTestContext()
        context.editorViewModel.enterEditMode()
        let environment = makeNotesDetailTestEnvironment()
        let hardwareKeyboardExpectation = MutableHardwareKeyboardExpectation(value: false)
        var presentations: [NoteFormattingBarPresentation] = []
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 390,
            autofocusEnabled: false,
            hardwareKeyboardInputExpectedProvider: { hardwareKeyboardExpectation.value },
            onFormattingBarPresentationChange: { presentations.append($0) },
            onEscape: nil
        )

        _ = mount(container, environment: environment)
        XCTAssertEqual(
            presentations.last,
            .floatingTopTrailing
        )

        hardwareKeyboardExpectation.value = true
        NotificationCenter.default.post(name: UITextInputMode.currentInputModeDidChangeNotification, object: nil)
        try await waitForFormattingBarPresentation(.floatingTopTrailing, in: presentations)

        XCTAssertEqual(presentations.last, .floatingTopTrailing)
    }

    private func waitForFormattingBarPresentation(
        _ expected: NoteFormattingBarPresentation,
        in presentations: @autoclosure @escaping () -> [NoteFormattingBarPresentation]
    ) async throws {
        let timeout = Date().addingTimeInterval(1.0)
        while Date() < timeout {
            if presentations().last == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for formatting bar presentation \(expected)")
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

#if os(iOS)
@MainActor
private final class MutableHardwareKeyboardExpectation {
    var value: Bool

    init(value: Bool) {
        self.value = value
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
#endif
