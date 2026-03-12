#if os(iOS)
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteTextEditorSurfaceTests: NotesDetailViewHostingTestCase {
    func testAttributedNoteEditorContainerPrefersUIKitSurfaceOnIOS() {
        XCTAssertEqual(AttributedNoteEditorContainer.preferredEditorSurfaceKind, .uiKit)
    }
    func testCanonicalSelectionUpdatesMoveTextViewCaretUsingUTF16Offsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("A👍🏽B"),
            plainText: "A👍🏽B"
        )
        viewModel.selection = viewModel.insertionPointSelection(
            forUTF16Offset: 5,
            in: viewModel.attributedContent
        )
        let textView = try mountTextView(viewModel: viewModel)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))
    }
    func testKeyboardAccessoryPresentationWrapsFormattingBarInAccessoryHost() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        let accessoryView = try XCTUnwrap(textView.inputAccessoryView)

        XCTAssertFalse(accessoryView is UIKitNoteFormattingBar)
        XCTAssertNotNil(findEmbeddedFormattingBar(in: accessoryView))
    }
    func testKeyboardAccessoryHostKeepsFormattingBarCompactAndTrailingAligned() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        let accessoryView = try XCTUnwrap(textView.inputAccessoryView)

        accessoryView.frame = CGRect(x: 0, y: 0, width: 390, height: 56)
        accessoryView.setNeedsLayout()
        accessoryView.layoutIfNeeded()

        let embeddedBar = try XCTUnwrap(findEmbeddedFormattingBar(in: accessoryView))

        XCTAssertLessThan(embeddedBar.frame.width, accessoryView.bounds.width)
        XCTAssertEqual(embeddedBar.frame.maxX, accessoryView.bounds.maxX - 12, accuracy: 0.5)
        XCTAssertEqual(embeddedBar.frame.width, embeddedBar.intrinsicContentSize.width, accuracy: 0.5)
    }
    func testKeyboardAccessoryHostAddsBottomInsetAboveKeyboard() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        let accessoryView = try XCTUnwrap(textView.inputAccessoryView)
        let embeddedBar = try XCTUnwrap(findEmbeddedFormattingBar(in: accessoryView))
        let fittedSize = accessoryView.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        accessoryView.frame = CGRect(origin: .zero, size: fittedSize)
        accessoryView.setNeedsLayout()
        accessoryView.layoutIfNeeded()

        XCTAssertGreaterThan(accessoryView.bounds.height, embeddedBar.intrinsicContentSize.height)
        XCTAssertEqual(
            embeddedBar.frame.maxY,
            accessoryView.bounds.maxY - 8,
            accuracy: 0.5
        )
    }
    func testKeyboardAccessoryHostUsesRequestedWidthWhenFitting() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        let accessoryView = try XCTUnwrap(textView.inputAccessoryView)
        let fittedSize = accessoryView.systemLayoutSizeFitting(
            CGSize(width: 390, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        XCTAssertEqual(fittedSize.width, 390, accuracy: 0.5)
        XCTAssertEqual(fittedSize.height, 56, accuracy: 0.5)
    }
    func testFloatingTopTrailingPresentationOmitsUIKitFormattingBarAccessory() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .floatingTopTrailing
        )
        XCTAssertNil(textView.inputAccessoryView)
    }
    func testHiddenPresentationOmitsUIKitFormattingBarAccessory() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .hidden
        )
        XCTAssertNil(textView.inputAccessoryView)
    }
    func testReadOnlySurfaceOmitsUIKitFormattingBarAccessory() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            isEditable: false,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        XCTAssertNil(textView.inputAccessoryView)
    }
    func testPhoneSurfaceDisablesDuplicateSystemFormattingUI() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled
        )
        XCTAssertFalse(textView.allowsEditingTextAttributes)
        XCTAssertNil(textView.textFormattingConfiguration)
    }
    func testPhoneSurfaceCommandBTriggersSharedBoldFormattingCommand() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let insertion = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        let textView = UIKitNoteTextEditorSurface.AccessoryTextView()
        let configuration = context.editorViewModel.noteFormattingBarConfiguration
        textView.formattingCommandsEnabled = configuration.isEnabled
        textView.onBoldCommand = configuration.onBoldTap
        let boldCommand = try XCTUnwrap(
            textView.keyCommands?.first {
                $0.input?.lowercased() == "b" && $0.modifierFlags == [.command]
            }
        )
        _ = textView.perform(boldCommand.action)
        XCTAssertTrue(context.editorViewModel.isFormattingActive(.bold))
    }
    func testIPadSurfaceCommandBTriggersSharedBoldFormattingCommandWithoutAccessoryBar() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let insertion = nativeViewModel.attributedContent.endIndex
        nativeViewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        let textView = UIKitNoteTextEditorSurface.AccessoryTextView()
        let configuration = context.editorViewModel.noteFormattingBarConfiguration
        textView.formattingCommandsEnabled = configuration.isEnabled
        textView.onBoldCommand = configuration.onBoldTap
        let boldCommand = try XCTUnwrap(
            textView.keyCommands?.first {
                $0.input?.lowercased() == "b" && $0.modifierFlags == [.command]
            }
        )
        _ = textView.perform(boldCommand.action)
        XCTAssertTrue(context.editorViewModel.isFormattingActive(.bold))
    }
    func testFirstResponderSurfaceReloadsInputViewsWhenAccessoryPresentationChanges() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let presentationState = FormattingPresentationState(.keyboardAccessory)
        let textView = ReloadTrackingAccessoryTextView()
        let controller = mountSurfaceHost(
            viewModel: viewModel,
            presentationState: presentationState,
            textView: textView
        )
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertNotNil(findEmbeddedFormattingBar(in: try XCTUnwrap(textView.inputAccessoryView)))
        XCTAssertEqual(textView.reloadInputViewsCallCount, 0)
        presentationState.presentation = .floatingTopTrailing
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(textView.reloadInputViewsCallCount, 1)
        XCTAssertNil(textView.inputAccessoryView)
    }
    func testEditableSurfaceBecomesFirstResponderOnMount() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            autofocusEnabled: true,
            attachToWindow: true,
            makeKeyAndVisible: true
        )
        XCTAssertTrue(textView.isFirstResponder)
    }

    func testNotesDetailViewTestRetainerResetDetachesHostedWindows() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        _ = try mountTextView(viewModel: viewModel, attachToWindow: true)
        let window = try XCTUnwrap(NotesDetailViewTestRetainer.hostingWindows.last)
        XCTAssertNotNil(window.rootViewController)
        NotesDetailViewTestRetainer.reset()
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingControllers.isEmpty)
        XCTAssertTrue(NotesDetailViewTestRetainer.hostingWindows.isEmpty)
        XCTAssertNil(window.rootViewController)
        XCTAssertTrue(window.isHidden)
    }
    func testEditableSurfaceSkipsFirstResponderWhenAutofocusDisabled() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel, autofocusEnabled: false)
        XCTAssertFalse(textView.isFirstResponder)
    }
    func testUIKitSurfaceUsesReadModeTextPaddingInsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        XCTAssertEqual(textView.textContainer.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset.left, NoteTextLayout.horizontalPadding)
        XCTAssertEqual(textView.textContainerInset.right, NoteTextLayout.horizontalPadding)
        XCTAssertEqual(textView.textContainerInset.top, NoteTextLayout.verticalPadding)
        XCTAssertEqual(textView.textContainerInset.bottom, NoteTextLayout.verticalPadding)
    }
    func testUIKitSelectionChangesFlowBackIntoCanonicalSelectionUsingUTF16Offsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("A👍🏽B"),
            plainText: "A👍🏽B"
        )
        let coordinator = UIKitNoteTextEditorSurface.Coordinator(viewModel: viewModel)
        let textView = UITextView()
        textView.attributedText = NSAttributedString(string: "A👍🏽B")
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: 5, length: 0)
        textView.delegate?.textViewDidChangeSelection?(textView)
        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 5
        )
    }
    func testUIKitTextChangesFlowBackIntoCanonicalContent() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let previous = viewModel.attributedContent
        textView.text = "Hello updated"
        textView.delegate?.textViewDidChange?(textView)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Hello updated")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertNotEqual(viewModel.attributedContent, previous)
    }
    func testCanonicalBoldFormattingRendersIntoUIKitAttributedText() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Bold"),
            plainText: "Bold"
        )
        let range = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)
        let textView = try mountTextView(viewModel: viewModel)
        let font = try XCTUnwrap(textView.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }
    func testInsertionPointFormattingToggleUpdatesUIKitTypingAttributes() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        let textView = try mountTextView(viewModel: viewModel)
        XCTAssertFalse(
            try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
                .fontDescriptor
                .symbolicTraits
                .contains(.traitBold)
        )
        viewModel.applyFormatting(.bold)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }
    func testUIKitSurfaceUsesDynamicLabelColorForExistingAndNewText() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let renderedColor = try XCTUnwrap(
            textView.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let typingColor = try XCTUnwrap(textView.typingAttributes[.foregroundColor] as? UIColor)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            renderedColor.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
        XCTAssertEqual(
            typingColor.resolvedColor(with: darkTraits),
            UIColor.label.resolvedColor(with: darkTraits)
        )
    }
    func testUIKitFormattedEditsDoNotStripExistingBoldFormatting() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Bold"),
            plainText: "Bold"
        )
        let range = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: range)
        viewModel.applyFormatting(.bold)
        let textView = try mountTextView(viewModel: viewModel)
        let updated = NSMutableAttributedString(attributedString: textView.attributedText)
        updated.append(NSAttributedString(string: "!"))
        textView.attributedText = updated
        textView.selectedRange = NSRange(location: updated.length, length: 0)
        textView.delegate?.textViewDidChange?(textView)
        let updatedRange = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Bold!")
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }
    func testPendingCaretTargetsStillLandAtCorrectInsertionPointWhenUIKitSurfaceMounts() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "A👍🏽B"))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.enterEditMode(at: .characterOffset(5))
        _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: nil
        )
        let textView = try mountTextView(viewModel: nativeViewModel)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))
    }
}

#endif
