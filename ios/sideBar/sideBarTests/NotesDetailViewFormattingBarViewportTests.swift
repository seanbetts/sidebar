#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesFormattingViewportTests: NotesDetailViewHostingTestCase {
    func testReadToEditActivationHandsViewportAndSelectionIntoEditorSurface() async throws {
        let plainText = (0..<40)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location

        readTextView.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        drainNotesHostingRunLoop()

        context.editorViewModel.enterEditMode(at: .characterOffset(targetOffset))
        XCTAssertNil(
            context.editorViewModel.debugPendingEditViewportOffset,
            "Edit entry should not carry read-surface viewport state into the live editor"
        )
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        XCTAssertTrue(context.editorViewModel.isEditingNote)
        XCTAssertEqual(editorTextView.selectedRange.location, targetOffset)
        XCTAssertEqual(editorTextView.selectedRange.length, 0)
        let selectionRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        XCTAssertTrue(
            editorTextView.visibleViewportRect().intersects(selectionRect.insetBy(dx: 0, dy: -1)),
            "Edit entry should rely on native selection visibility, not pending viewport restoration"
        )
    }

    func testReadToEditActivationFromBottomKeepsTargetLineVisible() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let targetOffset = NSString(string: plainText).range(of: "Line 79 body text").location
        let readBottomOffset = max(
            readTextView.contentSize.height
                + readTextView.adjustedContentInset.bottom
                - readTextView.bounds.height,
            -readTextView.adjustedContentInset.top
        )

        readTextView.setContentOffset(CGPoint(x: 0, y: readBottomOffset), animated: false)
        drainNotesHostingRunLoop()

        context.editorViewModel.enterEditMode(at: .characterOffset(targetOffset))
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        let selectionRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        let visibleViewport = editorTextView.visibleViewportRect()

        XCTAssertTrue(context.editorViewModel.isEditingNote)
        XCTAssertEqual(editorTextView.selectedRange.location, targetOffset)
        XCTAssertTrue(
            visibleViewport.intersects(selectionRect.insetBy(dx: 0, dy: -1)),
            "viewport=\(visibleViewport) selection=\(selectionRect) contentOffset=\(editorTextView.contentOffset)"
        )
    }

    func testVisibleTapSelectionAfterReadToEditKeepsViewportStable() async throws {
        let plainText = (0..<80)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let entryOffset = NSString(string: plainText).range(of: "Line 60 body text").location
        let tapOffset = NSString(string: plainText).range(of: "Line 58 body text").location
        let readOffset = max(
            readTextView.contentSize.height * 0.6,
            -readTextView.adjustedContentInset.top
        )

        readTextView.setContentOffset(CGPoint(x: 0, y: readOffset), animated: false)
        drainNotesHostingRunLoop()

        context.editorViewModel.enterEditMode(at: .characterOffset(entryOffset))
        drainNotesHostingRunLoop()
        drainNotesHostingRunLoop()

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            )
        )
        let baselineOffset = editorTextView.contentOffset.y

        simulateUIKitTouchSelectionChange(
            on: editorTextView,
            to: NSRange(location: tapOffset, length: 0)
        )
        await waitUntil {
            editorTextView.selectedRange.location == tapOffset
                && abs(editorTextView.contentOffset.y - baselineOffset) < 1
        }

        XCTAssertEqual(editorTextView.selectedRange.location, tapOffset)
        XCTAssertEqual(editorTextView.contentOffset.y, baselineOffset, accuracy: 1)
    }

    func testReadToEditActivationFromMiddlePreservesRelativeLinePosition() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(findTextView(in: controller.view))
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location

        let readTargetPosition = try XCTUnwrap(
            readTextView.position(from: readTextView.beginningOfDocument, offset: targetOffset)
        )
        let initialReadTargetRect = readTextView.caretRect(for: readTargetPosition)
        let readViewportHeight = readTextView.bounds.inset(by: readTextView.adjustedContentInset).height
        let targetReadOffset = max(
            initialReadTargetRect.midY - (readViewportHeight * 0.55),
            -readTextView.adjustedContentInset.top
        )
        readTextView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
        drainNotesHostingRunLoop()
        let readTargetRect = readTextView.caretRect(for: readTargetPosition)
        let readViewport = readTextView.bounds.inset(by: readTextView.adjustedContentInset)
        let expectedNormalizedViewportY = (readTargetRect.midY - readViewport.minY) / readViewport.height

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            normalizedViewportY: expectedNormalizedViewportY
        )
        await waitUntil {
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }

        let editorTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-editor-text-view"
            ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        )
        await waitUntil {
            guard let selectionRect = editorTextView.selectionRectInContentCoordinates() else {
                return false
            }
            let editorViewport = editorTextView.visibleViewportRect()
            let actualRelativeY = selectionRect.midY - editorViewport.minY
            let expectedRelativeY = editorViewport.height * expectedNormalizedViewportY
            return abs(actualRelativeY - expectedRelativeY) <= 24
        }

        let selectionRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        let editorViewport = editorTextView.visibleViewportRect()
        let actualRelativeY = selectionRect.midY - editorViewport.minY
        let expectedRelativeY = editorViewport.height * expectedNormalizedViewportY

        XCTAssertEqual(editorTextView.selectedRange.location, targetOffset)
        XCTAssertEqual(
            actualRelativeY,
            expectedRelativeY,
            accuracy: 24,
            "selectionRect=\(selectionRect) editorViewport=\(editorViewport) "
                + "contentOffset=\(editorTextView.contentOffset) "
                + "expectedNormalizedViewportY=\(expectedNormalizedViewportY)"
        )
    }

    func testFloatingPopoverTextStyleTapKeepsViewportStable() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let nativeViewModel = NativeNoteEditorViewModel()
        nativeViewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let trackingTextView = ViewportTrackingAccessoryTextView()
        let textView = try mountTextView(
            viewModel: nativeViewModel,
            makeKeyAndVisible: true,
            formattingBarPresentation: .floatingTopTrailing,
            makeTextView: { trackingTextView },
            maxContentWidth: 640,
            width: 500,
            height: 900
        )
        let window = try XCTUnwrap(textView.window)
        let bar = UIKitNoteFormattingBar(
            configuration: makeFormattingViewportConfiguration(for: nativeViewModel),
            presentation: .floatingTopTrailing
        )
        bar.frame = CGRect(x: 420, y: 16, width: 60, height: 48)
        window.addSubview(bar)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        let targetOffset = NSString(string: plainText).range(of: "Line 60 body text").location
        let targetRange = NSRange(location: targetOffset, length: 0)

        simulateUIKitSelectionChange(on: textView, to: targetRange)
        XCTAssertTrue(textView.becomeFirstResponder())
        textView.layoutIfNeeded()
        textView.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        drainNotesHostingRunLoop()
        let baselineOffset = textView.contentOffset.y

        bar.presentPopover()
        drainNotesHostingRunLoop()
        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertLessThan(abs(textView.contentOffset.y - baselineOffset), 1)

        let popoverRoot: UIView = try XCTUnwrap(findFormattingPopoverRoot(startingAt: window))
        let subheadingButton: UIButton = try XCTUnwrap(
            findDescendantButton(in: popoverRoot, accessibilityIdentifier: "note-formatting-text-style-subheading")
        )
        subheadingButton.sendActions(for: UIControl.Event.touchUpInside)
        drainNotesHostingRunLoop()

        XCTAssertEqual(textView.selectedRange, targetRange)
        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertLessThan(
            abs(textView.contentOffset.y - baselineOffset),
            1,
            "offset=\(textView.contentOffset) baseline=\(baselineOffset) "
                + "recordedOffsets=\(trackingTextView.recordedContentOffsets)"
        )
    }

    func testUIKitSurfaceAutofocusMountDoesNotCarryPendingViewportOffset() throws {
        let plainText = (0..<40)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadDocument(
            canonicalContent: canonicalUIKitPlainTextPass(plainText),
            plainText: plainText
        )
        let targetOffset = NSString(string: plainText).range(of: "Line 20 body text").location
        viewModel.selection = viewModel.insertionPointSelection(
            forUTF16Offset: targetOffset,
            in: viewModel.attributedContent
        )
        let trackingTextView = ViewportTrackingAccessoryTextView()

        let textView = try mountTextView(
            viewModel: viewModel,
            autofocusEnabled: true,
            attachToWindow: true,
            makeKeyAndVisible: true,
            formattingBarPresentation: .floatingTopTrailing,
            makeTextView: { trackingTextView },
            width: 900,
            height: 700
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(textView.isFirstResponder)
        XCTAssertNil(
            trackingTextView.debugPendingInitialViewportOffset,
            "Autofocus mount should not arm pending viewport restoration"
        )
    }
}

@MainActor
@available(iOS 26.0, *)
private func makeFormattingViewportConfiguration(
    for viewModel: NativeNoteEditorViewModel
) -> NoteFormattingBarConfiguration {
    NoteFormattingBarConfiguration(
        activeTextStyle: .body,
        isTextStyleSectionEnabled: true,
        isBodyTextStyleEnabled: true,
        isTitleTextStyleEnabled: true,
        isHeadingTextStyleEnabled: true,
        isSubheadingTextStyleEnabled: true,
        isBoldActive: false,
        isItalicActive: false,
        isUnderlineActive: false,
        isStrikethroughActive: false,
        isEnabled: true,
        onTextStyleSelection: { style in
            viewModel.setTextStyle(style)
        },
        onBoldTap: {
            viewModel.setFormatting(.bold, enabled: !viewModel.isFormattingActive(.bold))
        },
        onItalicTap: {
            viewModel.setFormatting(.italic, enabled: !viewModel.isFormattingActive(.italic))
        },
        onUnderlineTap: {
            viewModel.setFormatting(.underline, enabled: !viewModel.isFormattingActive(.underline))
        },
        onStrikethroughTap: {
            viewModel.setFormatting(.strikethrough, enabled: !viewModel.isFormattingActive(.strikethrough))
        }
    )
}

@MainActor
private func findDescendantButton(in view: UIView, accessibilityIdentifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
        return button
    }

    for subview in view.subviews {
        if let match = findDescendantButton(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }

    return nil
}

@MainActor
private func findFormattingPopoverRoot(startingAt view: UIView?) -> UIView? {
    guard let view else { return nil }
    if view.accessibilityIdentifier == "note-formatting-popover" {
        return view
    }

    for subview in view.subviews {
        if let match = findFormattingPopoverRoot(startingAt: subview) {
            return match
        }
    }

    return nil
}

@MainActor
private func findTextView(in view: UIView?, accessibilityIdentifier: String) -> UITextView? {
    guard let view else { return nil }
    if let textView = view as? UITextView, textView.accessibilityIdentifier == accessibilityIdentifier {
        return textView
    }

    for subview in view.subviews {
        if let match = findTextView(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
            return match
        }
    }

    return nil
}
#endif
