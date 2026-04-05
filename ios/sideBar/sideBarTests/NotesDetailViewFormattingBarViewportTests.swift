#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
final class NotesFormattingViewportTests: NotesDetailViewHostingTestCase {
    func testAnchoredReadToEditActivationKeepsCodeBlockBackgroundAlignedInMountedDetailView() async throws {
        let document = complexDecorationViewportDocument()
        let note = NotePayload(
            id: "code-decoration-note",
            name: "Decoration",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/code-decoration-note.md",
            modified: nil,
            created: nil
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
        let document = complexDecorationViewportDocument()
        let note = NotePayload(
            id: "blockquote-decoration-note",
            name: "Decoration",
            document: document,
            plainText: NotesSemanticDocumentProjection.plainText(from: document),
            path: "/blockquote-decoration-note.md",
            modified: nil,
            created: nil
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
        let expectedViewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )
        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false &&
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
            return abs(actualRelativeY - expectedViewportAnchorY) <= 24
        }

        let selectionRect = try XCTUnwrap(editorTextView.selectionRectInContentCoordinates())
        let editorViewport = editorTextView.visibleViewportRect()
        let actualRelativeY = selectionRect.midY - editorViewport.minY

        XCTAssertEqual(editorTextView.selectedRange.location, targetOffset)
        XCTAssertEqual(
            actualRelativeY,
            expectedViewportAnchorY,
            accuracy: 24,
            "selectionRect=\(selectionRect) editorViewport=\(editorViewport) "
                + "contentOffset=\(editorTextView.contentOffset) "
                + "expectedViewportAnchorY=\(expectedViewportAnchorY)"
        )
    }

    func testAnchoredReadToEditActivationKeepsEditorFirstResponderAfterHoldRelease() async throws {
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
        let viewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: viewportAnchorY
        )

        let editorTextView = try await waitForAnchoredEditorTextView(in: controller.view)

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false &&
                editorTextView.isFirstResponder
        }

        XCTAssertFalse(context.editorViewModel.isHoldingReadSurfaceDuringEditEntry)
        XCTAssertTrue(
            editorTextView.isFirstResponder,
            "Expected the first edit-entry tap to leave the editor focused after the read-surface hold is released."
        )
    }

    func testAnchoredReadToEditActivationKeepsReadSurfaceMountedAfterHoldRelease() async throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: plainText))
        let environment = makeNotesDetailTestEnvironment()
        let controller = mount(context.makeView(), environment: environment, makeKeyAndVisible: true)
        let readTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )
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
        let viewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: viewportAnchorY
        )

        _ = try await waitForAnchoredEditorTextView(in: controller.view)
        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
        }

        let heldReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        XCTAssertTrue(
            heldReadTextView === readTextView,
            "Hold release should not tear down and rebuild the read surface while the editor is already active."
        )
    }

    func testReadToEditActivationFromMiddleKeepsReadSurfaceMountedUntilViewportCorrectionCompletes() async throws {
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
        let expectedViewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )
        XCTAssertTrue(context.editorViewModel.isHoldingReadSurfaceDuringEditEntry)

        XCTAssertEqual(
            context.editorViewModel.presentationMode,
            .edit
        )

        await waitUntil(timeout: .seconds(2)) {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry == false
                && findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-editor-text-view"
                ) is UIKitNoteTextEditorSurface.AccessoryTextView
        }
    }

    func testReadToEditActivationFromMiddleKeepsHeldReadSurfaceAtExistingViewportOffset() async throws {
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
        let expectedViewportAnchorY = readTargetRect.midY - readViewport.minY

        context.editorViewModel.enterEditMode(
            at: .characterOffset(targetOffset),
            viewportAnchorY: expectedViewportAnchorY
        )

        await waitUntil {
            context.editorViewModel.isHoldingReadSurfaceDuringEditEntry &&
                findTextView(
                    in: controller.view,
                    accessibilityIdentifier: "notes-read-text-view"
                ) != nil
        }

        let heldReadTextView = try XCTUnwrap(
            findTextView(
                in: controller.view,
                accessibilityIdentifier: "notes-read-text-view"
            )
        )

        XCTAssertTrue(
            heldReadTextView === readTextView,
            "The live read surface should stay mounted during edit-entry hold instead of remounting a second read text view."
        )
        XCTAssertEqual(heldReadTextView.contentOffset.y, targetReadOffset, accuracy: 1)
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
private func waitForAnchoredEditorTextView(
    in rootView: UIView
) async throws -> UIKitNoteTextEditorSurface.AccessoryTextView {
    var resolvedTextView: UIKitNoteTextEditorSurface.AccessoryTextView?
    try await waitUntil(timeout: .seconds(2)) {
        resolvedTextView = findTextView(
            in: rootView,
            accessibilityIdentifier: "notes-editor-text-view"
        ) as? UIKitNoteTextEditorSurface.AccessoryTextView
        return resolvedTextView != nil
    }
    return try XCTUnwrap(resolvedTextView)
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

private extension NSRange {
    var nonNotFound: NSRange? {
        location == NSNotFound ? nil : self
    }
}

@MainActor
private func complexDecorationViewportDocument() -> NotesSemanticDocument {
    NotesSemanticDocument(
        version: NotesSemanticDocument.currentVersion,
        blocks: [
            .init(type: .heading, content: [.init(text: "Code Blocks", marks: [])]),
            .init(type: .subheading, content: [.init(text: "JavaScript", marks: [])]),
            .init(
                type: .codeBlock,
                content: [.init(
                    text: """
                    function greet(name) {
                    console.log('Hello, ${name}!');
                    return true;
                    }
                    """,
                    marks: []
                )]
            ),
            .init(type: .subheading, content: [.init(text: "Python", marks: [])]),
            .init(
                type: .codeBlock,
                content: [.init(
                    text: """
                    def calculate_sum(a, b):
                        return a + b
                    result = calculate_sum(5, 10)
                    print(f"Result: {result}")
                    """,
                    marks: []
                )]
            ),
            .init(type: .heading, content: [.init(text: "Blockquotes", marks: [])]),
            .init(type: .subheading, content: [.init(text: "Simple Blockquote", marks: [])]),
            .init(
                type: .blockquote,
                children: [
                    .paragraph([
                        .init(text: "This is a blockquote.\nIt can span multiple lines.", marks: [])
                    ])
                ]
            ),
            .paragraph([.init(text: String(repeating: "Trailing paragraph text. ", count: 30), marks: [])])
        ]
    )
}

@MainActor
private func anchoredReadViewportAnchorY(
    in textView: UITextView,
    targetOffset: Int
) throws -> CGFloat {
    let targetPosition = try XCTUnwrap(
        textView.position(from: textView.beginningOfDocument, offset: targetOffset)
    )
    let initialTargetRect = textView.caretRect(for: targetPosition)
    let viewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
    let targetReadOffset = max(
        initialTargetRect.midY - (viewportHeight * 0.55),
        -textView.adjustedContentInset.top
    )
    textView.setContentOffset(CGPoint(x: 0, y: targetReadOffset), animated: false)
    drainNotesHostingRunLoop()
    drainNotesHostingRunLoop()

    let targetRect = textView.caretRect(for: targetPosition)
    let viewport = textView.bounds.inset(by: textView.adjustedContentInset)
    return targetRect.midY - viewport.minY
}

@MainActor
private func anchoredEditorViewportAnchorY(
    in textView: UIKitNoteTextEditorSurface.AccessoryTextView,
    targetOffset: Int
) -> CGFloat? {
    guard let position = textView.position(from: textView.beginningOfDocument, offset: targetOffset) else {
        return nil
    }
    let rect = textView.caretRect(for: position)
    let viewport = textView.visibleViewportRect()
    guard viewport.height > 0 else { return nil }
    return rect.midY - viewport.minY
}

@MainActor
private func anchoredEditorGlyphRect(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGRect {
    let layoutManager = textView.layoutManager
    let textContainer = textView.textContainer
    textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
}

@MainActor
private func anchoredEditorBlockquoteRuleRect(
    in textView: UIKitNoteTextEditorSurface.AccessoryTextView,
    nearY: CGFloat
) throws -> CGRect {
    let rects = NoteTextBlockquoteDecorationLayout.detachedRuleRects(
        in: textView.attributedText,
        containerWidth: textView.bounds.width,
        textContainerInset: CGSize(
            width: textView.textContainerInset.left,
            height: textView.textContainerInset.top
        )
    )
    return try XCTUnwrap(
        rects.min(by: { abs($0.midY - nearY) < abs($1.midY - nearY) })
    )
}

@MainActor
private func anchoredEditorSamplePixelColor(
    in view: UIView,
    at point: CGPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) -> UIColor? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
        view.layer.render(in: context.cgContext)
    }
    guard let cgImage = image.cgImage,
          let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data else {
        XCTFail("Expected rendered pixel data", file: file, line: line)
        return nil
    }

    let pixelX = Int(point.x.rounded(.down))
    let pixelY = Int(point.y.rounded(.down))
    guard pixelX >= 0, pixelX < cgImage.width, pixelY >= 0, pixelY < cgImage.height else {
        XCTFail("Sample point out of bounds: \(point)", file: file, line: line)
        return nil
    }

    let bytes = CFDataGetBytePtr(data)
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let offset = (pixelY * cgImage.bytesPerRow) + (pixelX * bytesPerPixel)
    let alpha = CGFloat(bytes?[offset + 3] ?? 0) / 255
    guard alpha > 0 else { return UIColor(red: 0, green: 0, blue: 0, alpha: 0) }

    return UIColor(
        red: (CGFloat(bytes?[offset] ?? 0) / 255) / alpha,
        green: (CGFloat(bytes?[offset + 1] ?? 0) / 255) / alpha,
        blue: (CGFloat(bytes?[offset + 2] ?? 0) / 255) / alpha,
        alpha: alpha
    )
}

@MainActor
private func anchoredAssertColorsApproximatelyEqual(
    _ actual: UIColor,
    _ expected: UIColor,
    tolerance: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    var actualRed: CGFloat = 0
    var actualGreen: CGFloat = 0
    var actualBlue: CGFloat = 0
    var actualAlpha: CGFloat = 0
    var expectedRed: CGFloat = 0
    var expectedGreen: CGFloat = 0
    var expectedBlue: CGFloat = 0
    var expectedAlpha: CGFloat = 0

    XCTAssertTrue(
        actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
        file: file,
        line: line
    )
    XCTAssertTrue(
        expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha),
        file: file,
        line: line
    )

    XCTAssertEqual(actualRed, expectedRed, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualGreen, expectedGreen, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualBlue, expectedBlue, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: tolerance, file: file, line: line)
}
#endif
