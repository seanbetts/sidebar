import XCTest
import SwiftUI

#if os(macOS)
import AppKit
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewMountedMacOSTests: XCTestCase {
    func testWideMountedReadSurfaceKeepsScrollViewAtHostEdgeAndCentersReadableColumn() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\nTwo")
        let hostFrame = NSRect(x: 0, y: 0, width: 900, height: 240)
        let controller = NSHostingController(
            rootView: AnyView(
                SelectableNoteReadView(
                    document: document,
                    maxContentWidth: 640,
                    onActivateEditing: { _ in }
                )
            )
        )
        let window = NSWindow(
            contentRect: hostFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        controller.view.frame = hostFrame
        controller.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((hostFrame.width - 640) / 2)

        XCTAssertEqual(scrollView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.width, expectedHorizontalInset, accuracy: 0.5)
    }

    func testMountedReadSurfaceKeepsSelectableReadRenderer() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        XCTAssertEqual(textView.string, "One\nTwo")
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
    }

    func testMountedReadSurfaceTypographyMatchesMountedAppKitEditorForSameSemanticDocument() throws {
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let readTextView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: SelectableNoteReadView.makePlatformAttributedContent(
                from: document,
                baseFontSize: baseFontSize
            )
        )
        readTextView.frame = NSRect(x: 0, y: 0, width: 420, height: 280)
        readTextView.layoutSubtreeIfNeeded()

        let editorTextView = try mountEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )

        XCTAssertEqual(readTextView.string, editorTextView.string)
        XCTAssertEqual(
            try XCTUnwrap(readTextView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize,
            try XCTUnwrap(editorTextView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(readTextView.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont).pointSize,
            try XCTUnwrap(editorTextView.textStorage?.attribute(.font, at: 6, effectiveRange: nil) as? NSFont).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(readTextView.textStorage?.attribute(.font, at: 14, effectiveRange: nil) as? NSFont).pointSize,
            try XCTUnwrap(editorTextView.textStorage?.attribute(.font, at: 14, effectiveRange: nil) as? NSFont).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(readTextView.textStorage?.attribute(.font, at: 25, effectiveRange: nil) as? NSFont).pointSize,
            try XCTUnwrap(editorTextView.textStorage?.attribute(.font, at: 25, effectiveRange: nil) as? NSFont).pointSize,
            accuracy: 0.001
        )
    }

    func testMountedReadSurfaceUsesBaseReadableTextViewPaddingOnMacOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset.width, NoteTextLayout.horizontalPadding, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.height, NoteTextLayout.verticalPadding, accuracy: 0.001)
    }

    func testMountedReadSurfaceCanUnmountRepeatedlyWithoutCrashing() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\nTwo")

        for _ in 0..<notesLifetimeSmokeIterations {
            let controller = NSHostingController(
                rootView: AnyView(
                    SelectableNoteReadView(
                        document: document,
                        maxContentWidth: 420,
                        onActivateEditing: { _ in }
                    )
                )
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.orderFront(nil)
            _ = controller.view

            controller.rootView = AnyView(EmptyView())
            drainNotesHostingRunLoop()

            window.orderOut(nil)
            window.contentViewController = nil
            drainNotesHostingRunLoop()
        }
    }

    func testMountedReadSurfaceActivationReportsViewportAnchorOnMacOS() throws {
        let plainText = (0..<120)
            .map { index in "Line \(index) body text" }
            .joined(separator: "\n")
        let document = NotesSemanticDocumentProjection.document(fromPlainText: plainText)
        let hostFrame = NSRect(x: 0, y: 0, width: 900, height: 700)
        var capturedTarget: SelectableNoteReadView.ReadActivationTarget?
        var capturedViewportAnchorY: CGFloat?
        let controller = NSHostingController(
            rootView: AnyView(
                SelectableNoteReadView(
                    document: document,
                    maxContentWidth: 640,
                    onActivateEditingWithViewport: { target, viewportAnchorY in
                        capturedTarget = target
                        capturedViewportAnchorY = viewportAnchorY
                    }
                )
            )
        )
        let window = NSWindow(
            contentRect: hostFrame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.orderFront(nil)
        controller.view.frame = hostFrame
        controller.view.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let targetOffset = NSString(string: plainText).range(of: "Line 70 body text").location
        let readTargetRect = try glyphRect(in: textView, characterIndex: targetOffset)
        let targetReadOffset = max(
            readTargetRect.midY - (scrollView.contentView.bounds.height * 0.55),
            0
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetReadOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        drainNotesHostingRunLoop()

        let expectedViewportAnchorY = try viewportAnchorY(
            in: textView,
            scrollView: scrollView,
            characterIndex: targetOffset
        )
        let clickPoint = try makeSelectionPoint(
            in: textView,
            characterIndex: targetOffset,
            horizontalBias: 0.15
        )
        SelectableNoteReadView.activateEditingForTesting(
            in: textView,
            at: clickPoint
        )

        guard case .characterOffset(let activatedOffset)? = capturedTarget else {
            XCTFail("Expected character-offset activation target")
            return
        }
        let actualViewportAnchorY = try XCTUnwrap(capturedViewportAnchorY)
        XCTAssertEqual(activatedOffset, targetOffset)
        XCTAssertEqual(actualViewportAnchorY, expectedViewportAnchorY, accuracy: 2)
    }
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func viewportAnchorY(
    in textView: NSTextView,
    scrollView: NSScrollView,
    characterIndex: Int
) throws -> CGFloat {
    let rect = try glyphRect(in: textView, characterIndex: characterIndex)
    return textView.textContainerInset.height + rect.midY - scrollView.contentView.bounds.minY
}
#endif
