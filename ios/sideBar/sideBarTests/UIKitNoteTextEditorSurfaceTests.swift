#if os(iOS)
// swiftlint:disable file_length
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
// swiftlint:disable:next type_body_length
final class UIKitNoteTextEditorSurfaceTests: NotesDetailViewHostingTestCase {
    @MainActor
    final class AutofocusState: ObservableObject {
        @Published var isEnabled: Bool

        init(_ isEnabled: Bool) {
            self.isEnabled = isEnabled
        }
    }

    func testAttributedNoteEditorContainerPrefersUIKitSurfaceOnIOS() {
        XCTAssertEqual(AttributedNoteEditorContainer.preferredEditorSurfaceKind, .uiKit)
    }

    func testEditorSurfaceFillsHostHeightWhenSoftwareKeyboardIsNotVisible() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(canonicalContent: canonicalUIKitPlainTextPass("Hello"), plainText: "Hello")
        let textView = try mountTextView(viewModel: viewModel, width: 360, height: 320)
        let containerView = try XCTUnwrap(textView.superview)
        XCTAssertEqual(textView.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(textView.frame.height, containerView.bounds.height, accuracy: 0.5)
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
        XCTAssertEqual(
            fittedSize.height,
            NoteFormattingBarChrome.entryControlHeight + 8,
            accuracy: 0.5
        )
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
    func testPhoneSurfaceUsesGrayCaretTint() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled
        )
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            textView.tintColor.resolvedColor(with: darkTraits),
            UIColor.secondaryLabel.resolvedColor(with: darkTraits)
        )
    }
    func testPhoneSurfaceCommandBTriggersSharedBoldFormattingCommand() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Title\nHello"))
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
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Title\nHello"))
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
    func testIPadSurfaceExposesAppleTextStyleKeyboardShortcuts() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Title\nHello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let textView = UIKitNoteTextEditorSurface.AccessoryTextView()
        let configuration = context.editorViewModel.noteFormattingBarConfiguration
        textView.formattingCommandsEnabled = configuration.isEnabled
        textView.onBoldCommand = configuration.onBoldTap
        textView.onItalicCommand = configuration.onItalicTap
        textView.onUnderlineCommand = configuration.onUnderlineTap

        let commands = try XCTUnwrap(textView.keyCommands)

        XCTAssertNotNil(
            commands.first {
                $0.input?.lowercased() == "t" && $0.modifierFlags == [.command, .shift]
            }
        )
        XCTAssertNotNil(
            commands.first {
                $0.input?.lowercased() == "h" && $0.modifierFlags == [.command, .shift]
            }
        )
        XCTAssertNotNil(
            commands.first {
                $0.input?.lowercased() == "j" && $0.modifierFlags == [.command, .shift]
            }
        )
        XCTAssertNotNil(
            commands.first {
                $0.input?.lowercased() == "b" && $0.modifierFlags == [.command, .shift]
            }
        )
    }
    func testIPadSurfaceAppleTextStyleShortcutsApplyExpectedStyles() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Title\nHello"))
        let nativeViewModel = context.editorViewModel.makeNativeEditorViewModel()
        context.editorViewModel.attachNativeEditor(nativeViewModel)
        context.editorViewModel.enterEditMode()
        let target = nativeViewModel.index(forCharacterOffset: 6, in: nativeViewModel.attributedContent)
        nativeViewModel.selection = AttributedTextSelection(range: target..<target)
        let textView = UIKitNoteTextEditorSurface.AccessoryTextView()
        let configuration = context.editorViewModel.noteFormattingBarConfiguration
        textView.formattingCommandsEnabled = configuration.isEnabled
        textView.onTitleCommand = configuration.onTitleShortcut
        textView.onHeadingCommand = configuration.onHeadingShortcut
        textView.onSubheadingCommand = configuration.onSubheadingShortcut
        textView.onBodyCommand = configuration.onBodyShortcut

        let headingCommand = try XCTUnwrap(
            textView.keyCommands?.first {
                $0.input?.lowercased() == "h" && $0.modifierFlags == [.command, .shift]
            }
        )
        let subheadingCommand = try XCTUnwrap(
            textView.keyCommands?.first {
                $0.input?.lowercased() == "j" && $0.modifierFlags == [.command, .shift]
            }
        )
        let bodyCommand = try XCTUnwrap(
            textView.keyCommands?.first {
                $0.input?.lowercased() == "b" && $0.modifierFlags == [.command, .shift]
            }
        )

        _ = textView.perform(headingCommand.action)
        XCTAssertEqual(context.editorViewModel.activeTextStyle(), .heading)

        _ = textView.perform(subheadingCommand.action)
        XCTAssertEqual(context.editorViewModel.activeTextStyle(), .subheading)

        _ = textView.perform(bodyCommand.action)
        XCTAssertEqual(context.editorViewModel.activeTextStyle(), .body)
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

    func testEditableSurfaceCanDelayAutofocusUntilEnabledOnLaterUpdate() {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let autofocusState = AutofocusState(false)
        let textView = ReloadTrackingAccessoryTextView()
        let controller = mountAutofocusSurfaceHost(
            viewModel: viewModel,
            autofocusState: autofocusState,
            textView: textView
        )

        XCTAssertFalse(textView.isFirstResponder)

        autofocusState.isEnabled = true
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(textView.isFirstResponder)
    }

    func testEditableSurfaceAutofocusesPromptlyAfterWindowAttachment() {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = ReloadTrackingAccessoryTextView()
        let controller = UIHostingController(
            rootView: AnyView(
                AutofocusSurfaceHost(
                    autofocusState: AutofocusState(true),
                    viewModel: viewModel,
                    textView: textView
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 360, height: 320)

        controller.loadViewIfNeeded()
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(textView.isFirstResponder)

        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(
            textView.isFirstResponder,
            "Expected window attachment to trigger autofocus immediately rather than waiting for a later unrelated view update."
        )

        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)
    }

    func testEditableSurfaceClearsScheduledAutofocusAfterCanceledAttempt() {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let autofocusState = AutofocusState(true)
        let textView = ReloadTrackingAccessoryTextView()
        let controller = UIHostingController(
            rootView: AnyView(
                AutofocusSurfaceHost(
                    autofocusState: autofocusState,
                    viewModel: viewModel,
                    textView: textView
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 360, height: 320)
        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        autofocusState.isEnabled = false
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(textView.isFirstResponder)
        XCTAssertFalse(textView.hasScheduledAutofocus)

        autofocusState.isEnabled = true
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(textView.isFirstResponder)

        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)
    }

    private func mountAutofocusSurfaceHost(
        viewModel: NativeNoteEditorViewModel,
        autofocusState: AutofocusState,
        textView: ReloadTrackingAccessoryTextView,
        width: CGFloat = 360,
        height: CGFloat = 320
    ) -> UIHostingController<AnyView> {
        let controller = UIHostingController(
            rootView: AnyView(
                AutofocusSurfaceHost(
                    autofocusState: autofocusState,
                    viewModel: viewModel,
                    textView: textView
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
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
}

@MainActor
@available(iOS 26.0, *)
private struct AutofocusSurfaceHost: View {
    @ObservedObject var autofocusState: UIKitNoteTextEditorSurfaceTests.AutofocusState
    let viewModel: NativeNoteEditorViewModel
    let textView: ReloadTrackingAccessoryTextView

    var body: some View {
        UIKitNoteTextEditorSurface(
            viewModel: viewModel,
            maxContentWidth: 360,
            isEditable: true,
            shouldAutofocus: autofocusState.isEnabled,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .floatingTopTrailing,
            makeTextView: { textView }
        )
    }
}

#endif
