// swiftlint:disable file_length
import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
// swiftlint:disable type_body_length
final class SelectableNoteReadViewTests: XCTestCase {
    func testReadBaseFontSizeMatchesAppBodyTextSize() {
        XCTAssertEqual(
            SelectableNoteReadView.readBaseFontSize(for: .large),
            NoteTextTypography.defaultBodyFontSize(for: .large),
            accuracy: 0.001
        )
        XCTAssertEqual(
            SelectableNoteReadView.readBaseFontSize(for: .small),
            NoteTextTypography.defaultBodyFontSize(for: .small),
            accuracy: 0.001
        )
    }

    func testMakePlatformAttributedContentPreservesDistinctBlockTypography() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let titleFont = try noteReadPlatformFont(in: attributed, at: 0)
        let headingFont = try noteReadPlatformFont(in: attributed, at: 6)
        let subheadingFont = try noteReadPlatformFont(in: attributed, at: 14)

        XCTAssertEqual(attributed.string, "Title\nHeading\nSubheading")
        XCTAssertGreaterThan(noteReadPlatformFontPointSize(titleFont), noteReadPlatformFontPointSize(headingFont))
        XCTAssertGreaterThan(noteReadPlatformFontPointSize(headingFont), noteReadPlatformFontPointSize(subheadingFont))
    }

    func testMakePlatformAttributedContentAddsLeadingSpacingBeforeHeadingAndSubheading() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        let bodyStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle
        )
        let headingStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 11, effectiveRange: nil) as? NSParagraphStyle
        )
        let subheadingStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 19, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertGreaterThan(headingStyle.paragraphSpacingBefore, bodyStyle.paragraphSpacingBefore)
        XCTAssertGreaterThan(subheadingStyle.paragraphSpacingBefore, bodyStyle.paragraphSpacingBefore)
    }

    func testMakePlatformAttributedContentUsesCenteredChecklistAttachmentBounds() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Task", marks: [])], checked: true)
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let attachment = try XCTUnwrap(
            attributed.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )

        XCTAssertGreaterThan(attachment.bounds.height, 0)
        XCTAssertLessThan(attachment.bounds.minY, 0)
    }

    func testLogicalEditorSelectedRangeKeepsCaretOnEmptyChecklistLine() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "", marks: [])], checked: false),
                        .init(type: .listItem, content: [.init(text: "Next", marks: [])], checked: false)
                    ]
                )
            ]
        )
        let attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: 16
        )
        let editorAttributed = SelectableNoteReadView.bridgedPlatformEditorAttributedString(
            from: attributed,
            document: document,
            baseFontSize: 16
        )

        let logicalRange = SelectableNoteReadView.logicalEditorSelectedRange(
            fromDisplaySelectedRange: NSRange(location: 3, length: 0),
            in: editorAttributed,
            document: document
        )

        XCTAssertEqual(logicalRange, NSRange(location: 6, length: 0))
    }

    func testMakePlatformAttributedContentOmitsVisibleBlockquotePrefixInReadMode() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted", marks: [])]),
                        .paragraph([.init(text: "Again", marks: [])])
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        XCTAssertEqual(attributed.string, "Quoted\nAgain")
    }

    func testMakePlatformAttributedContentOmitsVisibleBlockquotePrefixAfterTypingTriggerRoundTrip() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
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

        noteAppendTypedText(">", to: viewModel)
        XCTAssertTrue(viewModel.handleTextReplacement(" "))

        let snapshot = viewModel.currentPersistenceSnapshot()
        let mixedDocument = NotesSemanticDocument(
            version: snapshot.document.version,
            blocks: snapshot.document.blocks + [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Existing", marks: [])])
                    ]
                )
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: mixedDocument,
            baseFontSize: 16
        )

        XCTAssertEqual(attributed.string, "Title\n\nExisting")
        XCTAssertFalse(attributed.string.contains("> "))
    }

    func testEditingActivationCharacterOffsetMapsReadBlockquoteOffsetsToLogicalOffsets() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted", marks: [])]),
                        .paragraph([.init(text: "Again", marks: [])])
                    ]
                )
            ]
        )

        XCTAssertEqual(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: 0
            ),
            2
        )
        XCTAssertEqual(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: 7
            ),
            11
        )
    }

    #if os(macOS)
    func testMakePlatformTextViewIsSelectableAndNonEditable() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Copy https://example.com", marks: [])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in }
        )

        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertEqual(textView.string, "Copy https://example.com")

        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
        let linkValue = textView.textStorage?.attribute(
            NSAttributedString.Key.link,
            at: 6,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)
    }

    func testMakePlatformTextViewUsesBaseReadableInsetsOnMacOS() throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\nTwo")
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 120)
        textView.layoutSubtreeIfNeeded()

        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.textContainerInset.width, NoteTextLayout.horizontalPadding, accuracy: 0.001)
        XCTAssertEqual(textView.textContainerInset.height, NoteTextLayout.verticalPadding, accuracy: 0.001)
    }

    func testMakePlatformTextViewKeepsFormattedDragSelectionsCopyableWithoutActivatingEditMode() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " and ", marks: []),
                    .init(text: "underlined", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in activationCount += 1 }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)

        let dragStart = try makeSelectionPoint(
            in: textView,
            characterIndex: 0,
            horizontalBias: 0.05
        )
        let dragEnd = try makeSelectionPoint(
            in: textView,
            characterIndex: textView.string.utf16.count - 1,
            horizontalBias: 0.95
        )
        try performDragSelection(in: textView, from: dragStart, to: dragEnd)

        let selected = try exportedSelection(from: textView)

        XCTAssertEqual(activationCount, 0)
        XCTAssertGreaterThan(textView.selectedRange().length, 0)
        XCTAssertEqual(String(selected.characters), "Bold and underlined")
        XCTAssertTrue(noteRangeHasBoldTrait(selected, range: noteCharacterRange(length: 4, in: selected)))

        let underlineStart = selected.index(selected.startIndex, offsetByCharacters: 9)
        XCTAssertTrue(noteRangeIsUnderlined(selected, range: underlineStart..<selected.endIndex))
    }

    func testMakePlatformTextViewFiresEditActivationAfterSingleClick() async throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Selectable text", marks: [.bold])
                ])
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        var activationCount = 0
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in activationCount += 1 }
        )
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)

        let clickPoint = try XCTUnwrap(nonLinkClickPoint(in: textView, characterIndex: 0))
        let mouseDown = try makeMouseEvent(
            type: .leftMouseDown,
            location: clickPoint,
            timestamp: 0,
            eventNumber: 0,
            pressure: 1
        )
        let mouseUp = try makeMouseEvent(
            type: .leftMouseUp,
            location: clickPoint,
            timestamp: 0.1,
            eventNumber: 1,
            pressure: 0
        )

        textView.mouseDown(with: mouseDown)
        textView.mouseUp(with: mouseUp)

        for _ in 0..<3 {
            drainNotesHostingRunLoop()
            await Task.yield()
        }
        await waitUntil(timeout: .milliseconds(150)) {
            activationCount == 1
        }
        XCTAssertEqual(activationCount, 1)
    }

    func testMakePlatformTextViewInstallsActivationClickRecognizer() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Selectable text", marks: [])
                ])
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let textView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: attributed,
            onActivateEditing: { _ in }
        )

        let clickRecognizers = textView.gestureRecognizers.compactMap { $0 as? NSClickGestureRecognizer }

        XCTAssertEqual(clickRecognizers.count, 1)
        XCTAssertEqual(clickRecognizers.first?.numberOfClicksRequired, 1)
    }

    func testMakePlatformAttributedContentPreservesBoldItalicUnderlineAndBaseSize() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .paragraph([
                    .init(text: "Bold", marks: [.bold]),
                    .init(text: " ", marks: []),
                    .init(text: "Italic", marks: [.italic]),
                    .init(text: " ", marks: []),
                    .init(text: "Underlined", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 17
        )

        let boldFont = try XCTUnwrap(
            attributed.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(notePlatformFontTraits(from: boldFont).bold)
        XCTAssertEqual(boldFont.pointSize, 17, accuracy: 0.001)

        let italicFont = try XCTUnwrap(
            attributed.attribute(.font, at: 11, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(notePlatformFontTraits(from: italicFont).italic)
        XCTAssertEqual(italicFont.pointSize, 17, accuracy: 0.001)

        let underlineValue = attributed.attribute(.underlineStyle, at: 18, effectiveRange: nil) as? Int
        XCTAssertEqual(underlineValue, NSUnderlineStyle.single.rawValue)
    }

    func testMakePlatformAttributedContentPreservesStrikethrough() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Active", marks: []),
                    .init(text: " ", marks: []),
                    .init(text: "Done", marks: [.strikethrough])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 17
        )

        let strikethroughValue = attributed.attribute(.strikethroughStyle, at: 7, effectiveRange: nil) as? Int
        XCTAssertEqual(strikethroughValue, NSUnderlineStyle.single.rawValue)
    }

    func testMakePlatformAttributedContentAppliesDerivedStrikethroughForCheckedChecklistItems() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Done", marks: [])], checked: true)
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 17
        )

        let strikethroughValue = attributed.attribute(.strikethroughStyle, at: 8, effectiveRange: nil) as? Int
        XCTAssertEqual(strikethroughValue, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(document.blocks[1].children?.first?.content.first?.marks, [])
    }

    func testMakePlatformAttributedContentRendersBulletGlyphsForUnorderedLists() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Second", marks: [])])
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        XCTAssertEqual(attributed.string, "Title\n• First\n• Second")
    }

    func testMakePlatformAttributedContentAppliesMutedColorForCheckedChecklistItems() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Done", marks: [])], checked: true)
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        #if os(macOS)
        XCTAssertNotNil(attributed.attribute(.attachment, at: 6, effectiveRange: nil))

        let markerColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        )
        let textColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
        )
        XCTAssertEqual(markerColor, .secondaryLabelColor)
        XCTAssertEqual(textColor, .secondaryLabelColor)
        #elseif os(iOS)
        XCTAssertNotNil(attributed.attribute(.attachment, at: 6, effectiveRange: nil))

        let markerColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? UIColor
        )
        let textColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? UIColor
        )
        XCTAssertEqual(markerColor, .secondaryLabel)
        XCTAssertEqual(textColor, .secondaryLabel)
        #endif
    }

    func testMakePlatformAttributedContentRendersChecklistMarkersWithSymbolAttachments() {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(
                    type: .checklist,
                    children: [
                        .init(type: .listItem, content: [.init(text: "Done", marks: [])], checked: true),
                        .init(type: .listItem, content: [.init(text: "Todo", marks: [])], checked: false)
                    ]
                )
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )

        XCTAssertEqual(attributed.string, "Title\n\u{FFFC} Done\n\u{FFFC} Todo")
        XCTAssertNotNil(attributed.attribute(.attachment, at: 6, effectiveRange: nil))
        XCTAssertNotNil(attributed.attribute(.attachment, at: 13, effectiveRange: nil))
        XCTAssertFalse(attributed.string.contains("[ ]"))
        XCTAssertFalse(attributed.string.contains("[x]"))
    }

    func testBridgedPlatformFontTraitsDoNotAddFormattingWithoutSwiftUIFont() throws {
        var attributed = AttributedString("Bold Italic Underline")

        let boldEnd = attributed.index(attributed.startIndex, offsetByCharacters: 4)
        let italicStart = attributed.index(boldEnd, offsetByCharacters: 1)
        let italicEnd = attributed.index(italicStart, offsetByCharacters: 6)
        let underlineStart = attributed.index(italicEnd, offsetByCharacters: 1)

        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: true, italic: false),
            to: &attributed,
            range: attributed.startIndex..<boldEnd
        )
        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: false, italic: true),
            to: &attributed,
            range: italicStart..<italicEnd
        )
        attributed[underlineStart..<attributed.endIndex].underlineStyle = .single

        let rendered = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: attributed,
            baseFontSize: 16
        )

        let boldFont = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(notePlatformFontTraits(from: boldFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: boldFont).italic)

        let italicFont = try XCTUnwrap(
            rendered.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        )
        XCTAssertFalse(notePlatformFontTraits(from: italicFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: italicFont).italic)

        let underlineValue = rendered.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int
        XCTAssertEqual(underlineValue, NSUnderlineStyle.single.rawValue)
    }

    func testBridgedPlatformAttributedStringPreservesStrikethroughWithoutSwiftUIFont() throws {
        var attributed = AttributedString("Active Done")
        let strikethroughStart = attributed.index(attributed.startIndex, offsetByCharacters: 7)
        attributed[strikethroughStart..<attributed.endIndex].strikethroughStyle = .single

        let rendered = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: attributed,
            baseFontSize: 16
        )

        let strikethroughValue = rendered.attribute(.strikethroughStyle, at: 7, effectiveRange: nil) as? Int
        XCTAssertEqual(strikethroughValue, NSUnderlineStyle.single.rawValue)
    }

    func testSwiftUIFontTraitsOverrideConflictingBridgedPlatformFontTraits() throws {
        var attributed = AttributedString("Italic")
        let range = attributed.startIndex..<attributed.endIndex
        attributed[range].font = noteInlineFont(baseFontSize: 16, bold: false, italic: true)
        applyBridgedPlatformFont(
            makePlatformFont(baseFontSize: 16, bold: true, italic: false),
            to: &attributed,
            range: range,
            clearSwiftUIFont: false
        )

        let rendered = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: attributed,
            baseFontSize: 16
        )

        let font = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = notePlatformFontTraits(from: font)
        XCTAssertFalse(traits.bold)
        XCTAssertTrue(traits.italic)
    }

    func testMakePlatformAttributedContentAppliesNoteTextParagraphMetrics() {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\n\nTwo")
        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document, baseFontSize: 16
        )
        let titleStyle = readAttributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let bodyStyle = readAttributed.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        let expectedTitle = NoteTextParagraphMetrics.paragraphStyle(for: .title, baseFontSize: 16)
        let expectedBody = NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: 16)
        XCTAssertNotNil(titleStyle)
        XCTAssertEqual(titleStyle?.lineSpacing ?? -1, expectedTitle.lineSpacing, accuracy: 0.001)
        XCTAssertEqual(titleStyle?.paragraphSpacing ?? -1, expectedTitle.paragraphSpacing, accuracy: 0.001)
        XCTAssertNotNil(bodyStyle)
        XCTAssertEqual(bodyStyle?.lineSpacing ?? -1, expectedBody.lineSpacing, accuracy: 0.001)
        XCTAssertEqual(bodyStyle?.paragraphSpacing ?? -1, expectedBody.paragraphSpacing, accuracy: 0.001)
    }

    func testReadTextViewBlankLineGapMatchesMountedEditorTextView() async throws {
        let document = NotesSemanticDocumentProjection.document(fromPlainText: "One\n\nTwo")
        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let readTextView = SelectableNoteReadView.makePlatformTextView(
            attributedContent: readAttributed,
            onActivateEditing: { _ in }
        )
        readTextView.frame = NSRect(x: 0, y: 0, width: 420, height: 240)

        let editorTextView = try mountEditorTextView(
            plainText: "One\n\nTwo",
            baseFontSize: 16,
            frame: NSRect(x: 0, y: 0, width: 420, height: 240)
        )

        let readGap = try lineGap(in: readTextView, fromCharacterAt: 0, toCharacterAt: 5)
        let editorGap = try lineGap(in: editorTextView, fromCharacterAt: 0, toCharacterAt: 5)

        XCTAssertEqual(
            readGap,
            editorGap,
            accuracy: 1.0,
            "readGap=\(readGap) editorGap=\(editorGap)"
        )
    }

    func testCharacterOffsetForEditingActivationClampsTapToRightOfLineToVisualLineEnd() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try lineEndOverflowClickPoint(in: textView, characterIndex: 2)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, 3)
    }

    func testCharacterOffsetForEditingActivationClampsTapBelowContentToEndOfNote() throws {
        let textView = try makeReadTextView(
            plainText: "One\nTwo",
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        )
        let tapPoint = try belowContentClickPoint(in: textView, characterIndex: 6)

        let offset = SelectableNoteReadView.characterOffsetForEditingActivation(
            in: textView,
            at: tapPoint
        )

        XCTAssertEqual(offset, textView.string.utf16.count)
    }
    #endif
}
// swiftlint:enable type_body_length
