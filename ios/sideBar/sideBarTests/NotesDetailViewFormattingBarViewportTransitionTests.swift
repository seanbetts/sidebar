#if os(iOS)
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, *)
extension NotesFormattingViewportTests {
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
                self.findTextView(
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
                && self.findTextView(
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
                self.findTextView(
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
}
#endif
