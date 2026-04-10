#if os(iOS)
// swiftlint:disable file_length
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class UIKitNoteTextEditorSurfaceEditingTests: NotesDetailViewHostingTestCase {
    final class FocusReportingTextView: UITextView {
        var isFocusedForTesting = false

        override var isFirstResponder: Bool {
            isFocusedForTesting
        }
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

    func testUIKitSelectionChangesDoNotPublishBackAfterTextViewLosesFirstResponder() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("abcdef"),
            plainText: "abcdef"
        )
        let coordinator = UIKitNoteTextEditorSurface.Coordinator(viewModel: viewModel)
        let textView = FocusReportingTextView()
        textView.attributedText = NSAttributedString(string: "abcdef")
        textView.delegate = coordinator
        textView.isFocusedForTesting = true
        textView.selectedRange = NSRange(location: 4, length: 0)
        textView.delegate?.textViewDidChangeSelection?(textView)
        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 4
        )

        textView.isFocusedForTesting = false
        textView.selectedRange = NSRange(location: 0, length: 0)
        textView.delegate?.textViewDidChangeSelection?(textView)

        assertUIKitInsertionPointUTF16Offset(
            viewModel.selection,
            in: viewModel.attributedContent,
            equals: 4
        )
    }

    func testUIKitTextChangesFlowBackIntoCanonicalContentOnNextMainActorTurn() async throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let textView = try mountTextView(viewModel: viewModel)
        let previous = viewModel.attributedContent
        textView.text = "Hello updated"
        textView.delegate?.textViewDidChange?(textView)

        XCTAssertEqual(String(viewModel.attributedContent.characters), String(previous.characters))
        await waitUntil(timeout: .seconds(1)) {
            String(viewModel.attributedContent.characters) == "Hello updated"
        }

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
            canonicalContent: canonicalUIKitPlainTextPass("Title\nHello"),
            plainText: "Title\nHello"
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

    func testTextStyleChangeDoesNotJumpFocusedViewportToEnd() throws {
        let plainText = (0..<40)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location
        let targetIndex = viewModel.index(forCharacterOffset: targetOffset, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: targetIndex..<targetIndex)

        let textView = try mountTextView(
            viewModel: viewModel,
            makeKeyAndVisible: true,
            formattingBarConfiguration: .disabled,
            formattingBarPresentation: .floatingTopTrailing,
            width: 834,
            height: 520
        )
        XCTAssertTrue(textView.becomeFirstResponder())
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(textView.isFirstResponder)

        textView.layoutIfNeeded()
        textView.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let baselineOffset = textView.contentOffset.y

        viewModel.applyTextStyle(.subheading)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(textView.selectedRange.location, targetOffset)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)
    }

    func testUIKitTypingAttributesStayPlainOnEmptyTrailingParagraphAfterHeading() throws {
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

        let textView = try mountTextView(viewModel: viewModel)
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)

        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testUIKitTypingAttributesStayPlainWhenTrailingBlockMarkerIsStripped() throws {
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

        let textView = try mountTextView(viewModel: viewModel)
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? UIFont)

        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testReturnKeyIsHandledBySharedBlockTransitionLayer() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let insertionPoint = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertionPoint..<insertionPoint)
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = viewModel.utf16SelectedRange(in: viewModel.attributedContent)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: "\n"
        ) ?? true

        XCTAssertFalse(handled)
        textView.insertText("Body")
        XCTAssertEqual(
            viewModel.currentPersistenceSnapshot().document.blocks.map(\.type),
            [.title, .heading, .paragraph]
        )
    }

    func testRangedReturnIsHandledBySharedStructuralMutationLayer() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = NSRange(location: 10, length: 1)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: "\n"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Head", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "ng", marks: [])])
    }

    func testMultilinePasteIsHandledBySharedStructuralMutationLayer() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(viewModel: viewModel)
        textView.selectedRange = NSRange(location: 13, length: 0)

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: " Alpha\nBeta"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Heading Alpha", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Beta", marks: [])])
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

        let expectation = XCTestExpectation(description: "formatted text change applied")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        let updatedRange = noteCharacterRange(length: 4, in: viewModel.attributedContent)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Bold!")
        XCTAssertTrue(noteRangeHasBoldTrait(viewModel.attributedContent, range: updatedRange))
    }

    func testPendingCaretTargetsStillLandAtCorrectInsertionPointWhenUIKitSurfaceMounts() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "A👍🏽B"))
        let nativeViewModel = NativeNoteEditorViewModel()
        context.editorViewModel.enterEditMode(at: .characterOffset(5))
        let pendingSelectionTarget = context.editorViewModel.consumePendingEditSelectionTarget()
        _ = AttributedNoteEditorContainer.loadNoteIfNeeded(
            editorViewModel: context.editorViewModel,
            nativeViewModel: nativeViewModel,
            loadedNoteId: nil
        )
        let textView = try mountTextView(
            viewModel: nativeViewModel,
            pendingSelectionTarget: pendingSelectionTarget
        )
        XCTAssertEqual(textView.selectedRange, NSRange(location: 5, length: 0))
    }

    func testPendingCaretTargetMountDoesNotPerformInitialSurfaceScroll() throws {
        let plainText = (0..<60)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let trackingTextView = ViewportTrackingAccessoryTextView()
        let pendingSelectionTarget = NotesEditorViewModel.PendingEditSelectionTarget.characterOffset(
            NSString(string: plainText).range(of: "Line 40 body text").location
        )

        _ = try mountTextView(
            viewModel: viewModel,
            autofocusEnabled: true,
            attachToWindow: true,
            makeKeyAndVisible: true,
            pendingSelectionTarget: pendingSelectionTarget,
            makeTextView: { trackingTextView },
            width: 834,
            height: 520
        )

        XCTAssertTrue(
            trackingTextView.recordedContentOffsets.isEmpty,
            "Surface mount should not scroll before the container handoff"
        )
    }
}

@MainActor
@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurfaceEditingTests {
    func testPureSelectionChangesDoNotRewriteUIKitAttributedText() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello\nWorld"),
            plainText: "Hello\nWorld"
        )
        let trackingTextView = AttributeMutationTrackingTextView()
        let controller = UIHostingController<AnyView>(
            rootView: AnyView(
                UIKitNoteTextEditorSurface(
                    viewModel: viewModel,
                    maxContentWidth: 360,
                    isEditable: true,
                    shouldAutofocus: false,
                    formattingBarConfiguration: .disabled,
                    formattingBarPresentation: .hidden,
                    makeTextView: { trackingTextView }
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 360, height: 320)
        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)

        let initialAssignmentCount = trackingTextView.attributedTextAssignmentCount
        let target = viewModel.index(forCharacterOffset: 3, in: viewModel.attributedContent)

        viewModel.selection = AttributedTextSelection(range: target..<target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(trackingTextView.attributedTextAssignmentCount, initialAssignmentCount)
        XCTAssertEqual(trackingTextView.selectedRange, NSRange(location: 3, length: 0))
    }

    func testPureSelectionChangesDoNotRequestFreshPersistenceSnapshots() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello\nWorld"),
            plainText: "Hello\nWorld"
        )
        let trackingTextView = AttributeMutationTrackingTextView()
        let controller = UIHostingController<AnyView>(
            rootView: AnyView(
                UIKitNoteTextEditorSurface(
                    viewModel: viewModel,
                    maxContentWidth: 360,
                    isEditable: true,
                    shouldAutofocus: false,
                    formattingBarConfiguration: .disabled,
                    formattingBarPresentation: .hidden,
                    makeTextView: { trackingTextView }
                )
            )
        )
        let frame = CGRect(x: 0, y: 0, width: 360, height: 320)
        let window = makeUIKitNoteTextEditorSurfaceHostingWindow(frame: frame)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        NotesDetailViewTestRetainer.hostingControllers.append(controller)
        NotesDetailViewTestRetainer.hostingWindows.append(window)

        var persistenceSnapshotCount = 0
        viewModel.onPersistenceSnapshotComputedForTesting = {
            persistenceSnapshotCount += 1
        }

        let target = viewModel.index(forCharacterOffset: 3, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: target..<target)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(persistenceSnapshotCount, 0)
    }

    func testTypingChangesDoNotRewriteUIKitAttributedTextOnNextUpdateCycle() throws {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass("Hello"),
            plainText: "Hello"
        )
        let trackingTextView = AttributeMutationTrackingTextView()
        let textView = try XCTUnwrap(
            mountTextView(
                viewModel: viewModel,
                formattingBarConfiguration: .disabled,
                formattingBarPresentation: .hidden,
                makeTextView: { trackingTextView }
            ) as? AttributeMutationTrackingTextView
        )
        let initialAssignmentCount = textView.attributedTextAssignmentCount
        let initialRenderGeneration = viewModel.renderGeneration

        textView.text = "Hello updated"
        textView.selectedRange = NSRange(location: 13, length: 0)
        textView.delegate?.textViewDidChange?(textView)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(textView.attributedTextAssignmentCount, initialAssignmentCount + 1)
        XCTAssertEqual(viewModel.renderGeneration, initialRenderGeneration)
        XCTAssertEqual(String(viewModel.attributedContent.characters), "Hello updated")
        XCTAssertEqual(
            viewModel.selection,
            viewModel.selection(
                fromUTF16Range: NSRange(location: 13, length: 0),
                in: viewModel.attributedContent
            )
        )
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
}

#endif
