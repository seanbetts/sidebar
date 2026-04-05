#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteTextEditorSurfaceTests: NotesDetailViewHostingTestCase {
    func testMountedAppKitChecklistDocumentRendersAttachmentMarkers() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Task", marks: [])], checked: false)
                    ]
                )
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        XCTAssertNotNil(textView.textStorage?.attribute(.attachment, at: 0, effectiveRange: nil))
    }

    func testEscapeCommandFromAppKitEditorSurfaceInvokesExitCallback() throws {
        var escapeCount = 0
        let textView = try mountEditorTextView(
            plainText: "Hello",
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180),
            onEscape: { escapeCount += 1 }
        )

        textView.cancelOperation(nil)

        XCTAssertEqual(escapeCount, 1)
    }

    func testWideMacOSContainerKeepsScrollViewAtHostEdgeAndCentersReadableColumn() async throws {
        let context = await makeNotesDetailViewTestContext(note: makeTestNote(plainText: "Hello"))
        let environment = makeNotesDetailTestEnvironment()
        let hostFrame = NSRect(x: 0, y: 0, width: 900, height: 320)
        let container = AttributedNoteEditorContainer(
            editorViewModel: context.editorViewModel,
            maxContentWidth: 640,
            onEscape: { _ in }
        )
        let controller = mount(container.environmentObject(environment), frame: hostFrame)
        controller.view.layoutSubtreeIfNeeded()
        controller.view.window?.contentView?.layoutSubtreeIfNeeded()
        drainNotesHostingRunLoop()

        let textView = try XCTUnwrap(findDescendantTextView(in: controller.view))
        let scrollView = try XCTUnwrap(textView.enclosingScrollView)
        let expectedHorizontalInset = NoteTextLayout.horizontalPadding + ((hostFrame.width - 640) / 2)

        XCTAssertEqual(scrollView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.frame.width, hostFrame.width, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerInset.width, expectedHorizontalInset, accuracy: 0.5)
    }

    func testMountedAppKitEditorUsesSharedTypographyAndParagraphMetrics() throws {
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
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )

        XCTAssertEqual(textView.string, "Title\nHeading\nSubheading\nBody")

        let titleFont = try fontAttribute(in: textView, at: 0)
        let headingFont = try fontAttribute(in: textView, at: 6)
        let subheadingFont = try fontAttribute(in: textView, at: 14)
        let bodyFont = try fontAttribute(in: textView, at: 25)

        XCTAssertEqual(
            titleFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .title, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            headingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .heading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            subheadingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .subheading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            bodyFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .body, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertTrue(notePlatformFontTraits(from: titleFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: headingFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: subheadingFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: bodyFont).bold)

        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .title, baseFontSize: baseFontSize),
            at: 0
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .heading, baseFontSize: baseFontSize),
            at: 6
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .subheading, baseFontSize: baseFontSize),
            at: 14
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize),
            at: 25
        )
    }

    func testMountedAppKitEditorUsesInlineCodeBackgroundAndMonospacedFont() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "code", marks: [.inlineCode])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        let font = try fontAttribute(in: textView, at: 0)
        let backgroundColor = try backgroundColorAttribute(in: textView, at: 0)

        XCTAssertTrue(notePlatformFontTraits(from: font).monospaced)
        XCTAssertEqual(backgroundColor, NoteTextAppearance.inlineCodeBackgroundColor)
    }

    func testMountedAppKitEditorDrawsCustomCodeBlockBackground() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        let font = try fontAttribute(in: textView, at: 0)
        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try glyphRect(in: textView, characterIndex: 9)
        let shortLineRect = try glyphRect(in: textView, characterIndex: 12)
        let samplePoint = NSPoint(
            x: textView.textContainerInset.width + shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: textView.textContainerInset.height + shortLineRect.midY
        )
        let editorRect = try XCTUnwrap(codeBlockBackgroundRects(in: textView).first)

        XCTAssertTrue(notePlatformFontTraits(from: font).monospaced)
        XCTAssertTrue(editorRect.contains(samplePoint))
    }

    func testMountedAppKitReadSurfaceDrawsCustomCodeBlockBackground() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])])
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        XCTAssertNil(textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try glyphRect(in: textView, characterIndex: 9)
        let shortLineRect = try glyphRect(in: textView, characterIndex: 12)
        let samplePoint = NSPoint(
            x: textView.textContainerInset.width + shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: textView.textContainerInset.height + shortLineRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor,
            NoteTextAppearance.codeBlockBackgroundColor,
            tolerance: 0.05
        )
    }

    func testMountedAppKitEditorDrawsDividerRule() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(type: .divider),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        let dividerRect = try XCTUnwrap(
            NoteTextDividerDecorationLayout.ruleRects(
                in: try XCTUnwrap(textView.textStorage),
                layoutManager: try XCTUnwrap(textView.layoutManager),
                textContainer: try XCTUnwrap(textView.textContainer),
                textContainerInset: textView.textContainerInset
            ).first
        )
        let beforeRect = try glyphRect(in: textView, characterIndex: 0).offsetBy(
            dx: textView.textContainerInset.width,
            dy: textView.textContainerInset.height
        )
        let afterRect = try glyphRect(in: textView, characterIndex: 8).offsetBy(
            dx: textView.textContainerInset.width,
            dy: textView.textContainerInset.height
        )
        let expectedWidth = textView.bounds.width - (textView.textContainerInset.width * 2) -
            (NoteTextAppearance.dividerHorizontalInset * 2)

        XCTAssertEqual(
            dividerRect.minX,
            textView.textContainerInset.width + NoteTextAppearance.dividerHorizontalInset,
            accuracy: 1
        )
        XCTAssertEqual(dividerRect.width, expectedWidth, accuracy: 1)
        XCTAssertGreaterThan(dividerRect.midY, beforeRect.midY)
        XCTAssertLessThan(dividerRect.midY, afterRect.midY)
    }

    func testMountedAppKitEditorAddsVerticalPaddingAroundCodeBlocks() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1\nprint(x)", marks: [])]),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let expectedGapAboveDelta = NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize)
        let expectedGapBelowDelta = NoteTextParagraphMetrics.codeBlockPaddingAfter(baseFontSize: baseFontSize)
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        let gapAbove = try lineGap(in: textView, fromCharacterAt: 0, toCharacterAt: 7)
        let internalGap = try lineGap(in: textView, fromCharacterAt: 7, toCharacterAt: 17)
        let gapBelow = try lineGap(in: textView, fromCharacterAt: 17, toCharacterAt: 26)

        XCTAssertGreaterThan(gapAbove - internalGap, expectedGapAboveDelta - 0.75)
        XCTAssertGreaterThan(gapBelow - internalGap, expectedGapBelowDelta - 0.75)
        XCTAssertGreaterThan(gapBelow - gapAbove, 2)
    }

    func testMountedAppKitEditorUsesSecondaryLabelCaretTint() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello"),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        XCTAssertEqual(textView.insertionPointColor, .secondaryLabelColor)
    }

    func testReturnKeyCreatesExpectedFollowupBlocksForTitleSubheadingAndBody() throws {
        let titleTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        titleTextView.setSelectedRange(NSRange(location: titleTextView.string.utf16.count, length: 0))

        let titleHandled = titleTextView.delegate?.textView?(
            titleTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(titleHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: titleTextView)?.document.blocks.map(\.type),
            [.title, .paragraph]
        )

        let subheadingTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .subheading, content: [.init(text: "Subheading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        subheadingTextView.setSelectedRange(NSRange(location: subheadingTextView.string.utf16.count, length: 0))

        let subheadingHandled = subheadingTextView.delegate?.textView?(
            subheadingTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(subheadingHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: subheadingTextView)?.document.blocks.map(\.type),
            [.title, .subheading, .paragraph]
        )

        let bodyTextView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .paragraph([.init(text: "Body", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        bodyTextView.setSelectedRange(NSRange(location: bodyTextView.string.utf16.count, length: 0))

        let bodyHandled = bodyTextView.delegate?.textView?(
            bodyTextView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ) ?? false

        XCTAssertTrue(bodyHandled)
        XCTAssertEqual(
            mountedEditorSnapshot(from: bodyTextView)?.document.blocks.map(\.type),
            [.title, .paragraph, .paragraph]
        )
    }

    func testRangedReturnIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: 10, length: 1))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: "\n"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Head", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "ng", marks: [])])
    }

    func testMultilinePasteIsHandledBySharedStructuralMutationLayerOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: 13, length: 0))

        let handled = textView.delegate?.textView?(
            textView,
            shouldChangeTextIn: textView.selectedRange(),
            replacementString: " Alpha\nBeta"
        ) ?? true

        XCTAssertFalse(handled)
        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .heading, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "Heading Alpha", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "Beta", marks: [])])
    }

    func testDoubleReturnExitsCodeBlockIntoParagraphBlockOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Snippet", marks: [])]),
                    .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertTrue(
            textView.delegate?.textView?(
                textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            ) ?? false
        )
        XCTAssertTrue(
            textView.delegate?.textView?(
                textView,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            ) ?? false
        )

        let snapshot = try XCTUnwrap(mountedEditorSnapshot(from: textView))
        XCTAssertEqual(snapshot.document.blocks.map(\.type), [.title, .codeBlock, .paragraph])
        XCTAssertEqual(snapshot.document.blocks[1].content, [.init(text: "let x = 1\n", marks: [])])
        XCTAssertEqual(snapshot.document.blocks[2].content, [.init(text: "", marks: [])])
    }

    func testTypingAttributesStayPlainOnEmptyTrailingParagraphAfterHeadingOnMacOS() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocument(
                version: NotesSemanticDocument.currentVersion,
                blocks: [
                    .init(type: .title, content: [.init(text: "Title", marks: [])]),
                    .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                    .paragraph([.init(text: "", marks: [])])
                ]
            ),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )
        let font = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)

        XCTAssertFalse(notePlatformFontTraits(from: font).bold)
    }
}

@MainActor
func mountedEditorSnapshot(
    from textView: NSTextView
) -> NativeNoteEditorViewModel.PersistenceSnapshot? {
    (textView.delegate as? AppKitNoteTextEditorSurface.Coordinator)?.viewModel.currentPersistenceSnapshot()
}

#endif
