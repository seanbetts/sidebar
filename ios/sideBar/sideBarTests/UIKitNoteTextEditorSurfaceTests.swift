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
            canonicalContent: canonicalPlainTextPass("A👍🏽B"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .keyboardAccessory
        )
        let accessoryView = try XCTUnwrap(textView.inputAccessoryView)

        accessoryView.frame = CGRect(x: 0, y: 0, width: 390, height: 44)
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
        XCTAssertEqual(fittedSize.height, 52, accuracy: 0.5)
    }
    func testFloatingTopTrailingPresentationOmitsUIKitFormattingBarAccessory() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel, autofocusEnabled: false)
        XCTAssertFalse(textView.isFirstResponder)
    }
    func testUIKitSurfaceUsesReadModeTextPaddingInsets() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("A👍🏽B"),
            plainText: "A👍🏽B"
        )
        let coordinator = UIKitNoteTextEditorSurface.Coordinator(viewModel: viewModel)
        let textView = UITextView()
        textView.attributedText = NSAttributedString(string: "A👍🏽B")
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: 5, length: 0)
        textView.delegate?.textViewDidChangeSelection?(textView)
        assertInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 5
        )
    }
    func testUIKitTextChangesFlowBackIntoCanonicalContent() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Bold"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Hello"),
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
            canonicalContent: canonicalPlainTextPass("Bold"),
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

@MainActor
@available(iOS 26.0, *)
private func mountTextView(
    viewModel: NativeNoteEditorViewModel,
    isEditable: Bool = true,
    autofocusEnabled: Bool = false,
    attachToWindow: Bool = true,
    makeKeyAndVisible: Bool = false,
    formattingBarConfiguration: NoteFormattingBarConfiguration? = nil,
    formattingBarPresentation: NoteFormattingBarPresentation = .keyboardAccessory,
    width: CGFloat = 360,
    height: CGFloat = 320
) throws -> UITextView {
    let controller = UIHostingController<AnyView>(
        rootView: AnyView(
            UIKitNoteTextEditorSurface(
                viewModel: viewModel,
                maxContentWidth: width,
                isEditable: isEditable,
                shouldAutofocus: autofocusEnabled,
                formattingBarConfiguration: formattingBarConfiguration,
                formattingBarPresentation: formattingBarPresentation
            )
        )
    )
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    if attachToWindow {
        let window = makeHostingWindow(frame: frame)
        window.rootViewController = controller
        if makeKeyAndVisible {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = false
        }
        NotesDetailViewTestRetainer.hostingWindows.append(window)
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    } else {
        controller.loadViewIfNeeded()
        let hostView = UIView(frame: frame)
        hostView.addSubview(controller.view)
        controller.view.frame = hostView.bounds
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return try XCTUnwrap(findTextView(in: controller.view))
}

@MainActor
private func findTextView(in view: UIView) -> UITextView? {
    if let textView = view as? UITextView {
        return textView
    }
    for subview in view.subviews {
        if let match = findTextView(in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private func makeHostingWindow(frame: CGRect) -> UIWindow {
    guard let windowScene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first else {
        fatalError("Expected UIWindowScene for UIKit notes editor surface tests")
    }
    let window = UIWindow(windowScene: windowScene)
    window.frame = frame
    return window
}

@MainActor
@available(iOS 26.0, *)
private func mountSurfaceHost(
    viewModel: NativeNoteEditorViewModel,
    presentationState: FormattingPresentationState,
    textView: ReloadTrackingAccessoryTextView,
    width: CGFloat = 360,
    height: CGFloat = 320
) -> UIHostingController<AnyView> {
    let controller = UIHostingController<AnyView>(
        rootView: AnyView(
            FormattingSurfaceHost(
                presentationState: presentationState,
                viewModel: viewModel,
                textView: textView
            )
        )
    )
    let frame = CGRect(x: 0, y: 0, width: width, height: height)
    let window = makeHostingWindow(frame: frame)
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = frame
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    NotesDetailViewTestRetainer.hostingControllers.append(controller)
    NotesDetailViewTestRetainer.hostingWindows.append(window)
    return controller
}

@MainActor
@available(iOS 26.0, *)
private final class FormattingPresentationState: ObservableObject {
    @Published var presentation: NoteFormattingBarPresentation
    init(_ presentation: NoteFormattingBarPresentation) {
        self.presentation = presentation
    }
}

@MainActor
@available(iOS 26.0, *)
private final class ReloadTrackingAccessoryTextView: UIKitNoteTextEditorSurface.AccessoryTextView {
    private(set) var reloadInputViewsCallCount = 0
    override func reloadInputViews() {
        reloadInputViewsCallCount += 1
        super.reloadInputViews()
    }
}

@MainActor
@available(iOS 26.0, *)
private struct FormattingSurfaceHost: View {
    @ObservedObject var presentationState: FormattingPresentationState
    let viewModel: NativeNoteEditorViewModel
    let textView: ReloadTrackingAccessoryTextView

    var body: some View {
        UIKitNoteTextEditorSurface(
            viewModel: viewModel,
            maxContentWidth: 360,
            isEditable: true,
            shouldAutofocus: true,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: presentationState.presentation,
            makeTextView: { textView }
        )
    }
}

@available(iOS 26.0, *)
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

@available(iOS 26.0, *)
private func findEmbeddedFormattingBar(in view: UIView) -> UIKitNoteFormattingBar? {
    for subview in view.subviews {
        if let bar = subview as? UIKitNoteFormattingBar {
            return bar
        }
        if let nested = findEmbeddedFormattingBar(in: subview) {
            return nested
        }
    }

    return nil
}

private func canonicalPlainTextPass(_ plainText: String) -> String {
    NotesSemanticDocumentCodec.encode(
        NotesSemanticDocumentProjection.document(fromPlainText: plainText)
    ) ?? plainText
}
#endif
