#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesFormattingViewportTests: NotesDetailViewHostingTestCase {
    func testAnchoredReadToEditActivationKeepsCodeBlockBackgroundAlignedInMountedDetailView() async throws {
        let note = makeComplexDecorationViewportNote(
            id: "code-decoration-note",
            path: "/code-decoration-note.md"
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 516, height: 887),
            makeKeyAndVisible: true
        )
        controller.view.window?.overrideUserInterfaceStyle = .dark
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        drainNotesHostingRunLoop()
        let readTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let readPlainText = readTextView.attributedText.string as NSString
        let targetOffset = readPlainText.range(of: "function greet(name) {").location
        XCTAssertNotEqual(targetOffset, NSNotFound)

        let expectedViewportAnchorY = try anchoredReadViewportAnchorY(
            in: readTextView,
            targetOffset: targetOffset
        )
        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )

        let editorTextView = try await waitForAnchoredEditorTextView(in: controller.view)
        let renderView = try XCTUnwrap(editorTextView.superview)

        await waitUntil(timeout: .seconds(2)) {
            guard context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false else {
                return false
            }
            guard let firstLineRange = (editorTextView.attributedText.string as NSString)
                .range(of: "function greet(name) {").nonNotFound else {
                return false
            }
            return anchoredEditorViewportAnchorY(
                in: editorTextView,
                targetOffset: firstLineRange.location
            ).map { abs($0 - expectedViewportAnchorY) <= 24 } == true
        }

        let plainText = editorTextView.attributedText.string as NSString
        let firstLineRange = try XCTUnwrap(plainText.range(of: "function greet(name) {").nonNotFound)
        let secondLineRange = try XCTUnwrap(
            plainText.range(of: "console.log('Hello, ${name}!');").nonNotFound
        )
        let firstLineRect = try anchoredEditorGlyphRect(
            in: editorTextView,
            characterIndex: firstLineRange.location
        ).offsetBy(
            dx: editorTextView.textContainerInset.left,
            dy: editorTextView.textContainerInset.top
        )
        let secondLineRect = try anchoredEditorGlyphRect(
            in: editorTextView,
            characterIndex: secondLineRange.location + secondLineRange.length - 1
        ).offsetBy(
            dx: editorTextView.textContainerInset.left,
            dy: editorTextView.textContainerInset.top
        )
        let samplePoint = CGPoint(
            x: firstLineRect.maxX + ((secondLineRect.maxX - firstLineRect.maxX) * 0.5),
            y: firstLineRect.midY - editorTextView.contentOffset.y
        )
        let sampledColor = try XCTUnwrap(
            anchoredEditorSamplePixelColor(in: renderView, at: samplePoint)
        )
        anchoredAssertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: renderView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: renderView.traitCollection),
            tolerance: 0.05
        )
    }

    func testAnchoredReadToEditActivationKeepsBlockquoteRuleAlignedInMountedDetailView() async throws {
        let note = makeComplexDecorationViewportNote(
            id: "blockquote-decoration-note",
            path: "/blockquote-decoration-note.md"
        )
        let context = await makeNotesDetailViewTestContext(note: note)
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(
            context.makeView().environmentObject(environment),
            frame: CGRect(x: 0, y: 0, width: 516, height: 887),
            makeKeyAndVisible: true
        )
        controller.view.window?.overrideUserInterfaceStyle = .dark
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        drainNotesHostingRunLoop()
        let readTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
        let readPlainText = readTextView.attributedText.string as NSString
        let targetOffset = readPlainText.range(of: "This is a blockquote.").location
        XCTAssertNotEqual(targetOffset, NSNotFound)

        let expectedViewportAnchorY = try anchoredReadViewportAnchorY(
            in: readTextView,
            targetOffset: targetOffset
        )
        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )

        let editorTextView = try await waitForAnchoredEditorTextView(in: controller.view)
        let renderView = try XCTUnwrap(editorTextView.superview)

        await waitUntil(timeout: .seconds(2)) {
            guard context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false else {
                return false
            }
            guard let quoteRange = (editorTextView.attributedText.string as NSString)
                .range(of: "This is a blockquote.").nonNotFound else {
                return false
            }
            return anchoredEditorViewportAnchorY(
                in: editorTextView,
                targetOffset: quoteRange.location
            ).map { abs($0 - expectedViewportAnchorY) <= 24 } == true
        }

        let plainText = editorTextView.attributedText.string as NSString
        let quoteRange = try XCTUnwrap(plainText.range(of: "This is a blockquote.").nonNotFound)
        let quoteRect = try anchoredEditorGlyphRect(
            in: editorTextView,
            characterIndex: quoteRange.location
        ).offsetBy(
            dx: editorTextView.textContainerInset.left,
            dy: editorTextView.textContainerInset.top
        )
        let ruleRect = try anchoredEditorBlockquoteRuleRect(
            in: editorTextView,
            nearY: quoteRect.midY
        )
        let samplePoint = CGPoint(
            x: ruleRect.midX,
            y: ruleRect.midY - editorTextView.contentOffset.y
        )
        let sampledColor = try XCTUnwrap(
            anchoredEditorSamplePixelColor(in: renderView, at: samplePoint)
        )

        anchoredAssertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: renderView.traitCollection),
            UIColor.separator.resolvedColor(with: renderView.traitCollection),
            tolerance: 0.08
        )
    }

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
        let targetLineOffset = NSString(string: plainText).range(of: "Line 79 body text").location
        let readBottomOffset = max(
            readTextView.contentSize.height
                + readTextView.adjustedContentInset.bottom
                - readTextView.bounds.height,
            -readTextView.adjustedContentInset.top
        )

        readTextView.setContentOffset(CGPoint(x: 0, y: readBottomOffset), animated: false)
        drainNotesHostingRunLoop()
        let targetPosition = try XCTUnwrap(
            readTextView.position(from: readTextView.beginningOfDocument, offset: targetLineOffset)
        )
        let targetCaretRect = readTextView.caretRect(for: targetPosition)
        let tapPoint = CGPoint(x: targetCaretRect.midX, y: targetCaretRect.midY)
        let targetOffset = try XCTUnwrap(
            SelectableNoteReadView.characterOffsetForEditingActivation(
                in: readTextView,
                at: tapPoint
            )
        )
        let readTargetPosition = try XCTUnwrap(
            readTextView.position(from: readTextView.beginningOfDocument, offset: targetOffset)
        )
        let readTargetRect = readTextView.caretRect(for: readTargetPosition)
        let readViewport = readTextView.bounds.inset(by: readTextView.adjustedContentInset)
        let viewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: viewportAnchorY
        )
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
            "viewport=\(visibleViewport) selection=\(selectionRect) "
                + "contentOffset=\(editorTextView.contentOffset) "
                + "contentSize=\(editorTextView.contentSize) "
                + "adjustedInset=\(editorTextView.adjustedContentInset)"
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

}
private extension NSRange {
    var nonNotFound: NSRange? {
        location == NSNotFound ? nil : self
    }
}
#endif
