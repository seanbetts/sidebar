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
}
#endif
