import XCTest
import SwiftUI

#if os(macOS)
import AppKit
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewMountedMacOSTests: XCTestCase {
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

    func testMountedReadSurfaceUsesZeroInternalTextViewPaddingOnMacOS() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset, .zero)
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
