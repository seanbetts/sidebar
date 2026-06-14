import XCTest
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewTypographyTests: XCTestCase {
    func testCodeBlockInlineCodeDoesNotUseInlineBackground() {
        XCTAssertNil(
            NoteTextAppearance.backgroundColor(
                for: .codeBlock,
                inlineCode: true
            )
        )
    }

    func testSharedTextStyleTypographyUsesApprovedScalesAndWeights() throws {
        let baseFontSize: CGFloat = 16

        let titleFont = NoteTextStyleTypography.platformFont(for: NoteTextStyle.title, baseFontSize: baseFontSize)
        let headingFont = NoteTextStyleTypography.platformFont(for: NoteTextStyle.heading, baseFontSize: baseFontSize)
        let subheadingFont = NoteTextStyleTypography.platformFont(for: NoteTextStyle.subheading, baseFontSize: baseFontSize)
        let bodyFont = NoteTextStyleTypography.platformFont(for: NoteTextStyle.body, baseFontSize: baseFontSize)

        XCTAssertEqual(titleFont.pointSize, baseFontSize * 1.75, accuracy: 0.001)
        XCTAssertEqual(headingFont.pointSize, baseFontSize * 1.4, accuracy: 0.001)
        XCTAssertEqual(subheadingFont.pointSize, baseFontSize * 1.15, accuracy: 0.001)
        XCTAssertEqual(bodyFont.pointSize, baseFontSize * 1.0, accuracy: 0.001)
        XCTAssertEqual(NoteTextStyleTypography.fontWeight(for: .title), .bold)
        XCTAssertEqual(NoteTextStyleTypography.fontWeight(for: .heading), .bold)
        XCTAssertEqual(NoteTextStyleTypography.fontWeight(for: .subheading), .bold)
        XCTAssertEqual(NoteTextStyleTypography.platformWeight(for: .title), .bold)
        XCTAssertEqual(NoteTextStyleTypography.platformWeight(for: .heading), .bold)
        XCTAssertEqual(NoteTextStyleTypography.platformWeight(for: .subheading), .bold)

        XCTAssertTrue(fontHasBoldTrait(titleFont))
        XCTAssertTrue(fontHasBoldTrait(headingFont))
        XCTAssertTrue(fontHasBoldTrait(subheadingFont))
        XCTAssertFalse(fontHasBoldTrait(bodyFont))
    }

    func testMakePlatformAttributedContentUsesSharedTextStyleTypographyTokens() throws {
        let baseFontSize: CGFloat = 16
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .init(type: .paragraph, content: [.init(text: "Body", marks: [])])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(
            try fontPointSize(in: attributed, at: 0),
            NoteTextStyleTypography.platformFont(for: .title, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try fontPointSize(in: attributed, at: 6),
            NoteTextStyleTypography.platformFont(for: .heading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try fontPointSize(in: attributed, at: 14),
            NoteTextStyleTypography.platformFont(for: .subheading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try fontPointSize(in: attributed, at: 25),
            NoteTextStyleTypography.platformFont(for: .body, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(try fontWeight(in: attributed, at: 0), try fontWeight(in: attributed, at: 25))
        XCTAssertGreaterThan(try fontWeight(in: attributed, at: 6), try fontWeight(in: attributed, at: 25))
        XCTAssertGreaterThan(try fontWeight(in: attributed, at: 14), try fontWeight(in: attributed, at: 25))
    }

    func testSharedParagraphMetricsUseCompactStyleSpecificSpacing() throws {
        let baseFontSize: CGFloat = 16

        let titleStyle = NoteTextParagraphMetrics.paragraphStyle(for: .title, baseFontSize: baseFontSize)
        let headingStyle = NoteTextParagraphMetrics.paragraphStyle(for: .heading, baseFontSize: baseFontSize)
       let subheadingStyle = NoteTextParagraphMetrics.paragraphStyle(for: .subheading, baseFontSize: baseFontSize)
        let bodyStyle = NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize)

        XCTAssertEqual(titleStyle.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(headingStyle.paragraphSpacingBefore, baseFontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(subheadingStyle.paragraphSpacingBefore, baseFontSize * 0.5, accuracy: 0.001)
        XCTAssertEqual(bodyStyle.paragraphSpacingBefore, 0, accuracy: 0.001)

        XCTAssertEqual(titleStyle.paragraphSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(headingStyle.paragraphSpacing, 3, accuracy: 0.001)
        XCTAssertEqual(subheadingStyle.paragraphSpacing, 2, accuracy: 0.001)
        XCTAssertEqual(bodyStyle.paragraphSpacing, 4, accuracy: 0.001)

        XCTAssertEqual(titleStyle.lineSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(headingStyle.lineSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(subheadingStyle.lineSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(bodyStyle.lineSpacing, 0, accuracy: 0.001)
    }

    func testNoteBlockLayoutMetricsExposeCurrentBlockSpacingAndIndents() throws {
        let baseFontSize: CGFloat = 16
        let context = NoteBlockLayoutContext(baseFontSize: baseFontSize)

        let title = NoteBlockLayout.metrics(for: .title, context: context)
        let heading = NoteBlockLayout.metrics(for: .heading, context: context)
        let subheading = NoteBlockLayout.metrics(for: .subheading, context: context)
        let paragraph = NoteBlockLayout.metrics(for: .paragraph, context: context)
        let unorderedList = NoteBlockLayout.metrics(for: .unorderedList, context: context)
        let orderedList = NoteBlockLayout.metrics(for: .orderedList, context: context)
        let checklist = NoteBlockLayout.metrics(for: .checklist, context: context)
        let blockquote = NoteBlockLayout.metrics(for: .blockquote, context: context)
        let codeBlock = NoteBlockLayout.metrics(for: .codeBlock, context: context)

        XCTAssertEqual(title.spacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(title.spacingAfter, baseFontSize * 0.25, accuracy: 0.001)
        XCTAssertEqual(heading.spacingBefore, baseFontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(heading.spacingAfter, baseFontSize * 0.1875, accuracy: 0.001)
        XCTAssertEqual(subheading.spacingBefore, baseFontSize * 0.5, accuracy: 0.001)
        XCTAssertEqual(subheading.spacingAfter, baseFontSize * 0.125, accuracy: 0.001)
        XCTAssertEqual(paragraph.spacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(paragraph.spacingAfter, 4, accuracy: 0.001)

        XCTAssertEqual(unorderedList.headIndent, baseFontSize, accuracy: 0.001)
        XCTAssertEqual(checklist.headIndent, baseFontSize, accuracy: 0.001)
        XCTAssertEqual(orderedList.firstLineHeadIndent, baseFontSize, accuracy: 0.001)
        XCTAssertEqual(orderedList.headIndent, baseFontSize * 2.5, accuracy: 0.001)
        XCTAssertEqual(orderedList.tabStops.first?.location ?? 0, baseFontSize * 2.5, accuracy: 0.001)
        XCTAssertEqual(orderedList.defaultTabInterval, baseFontSize * 2.5, accuracy: 0.001)
        XCTAssertEqual(blockquote.spacingBefore, 8, accuracy: 0.001)
        XCTAssertEqual(blockquote.spacingAfter, 8, accuracy: 0.001)
        XCTAssertEqual(blockquote.headIndent, baseFontSize * 1.25, accuracy: 0.001)
        XCTAssertEqual(codeBlock.headIndent, baseFontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(codeBlock.tailIndent, baseFontSize * 0.75, accuracy: 0.001)
    }

    func testNoteBlockLayoutOnlyAddsListSpacingAfterContiguousListRuns() throws {
        let baseFontSize: CGFloat = 16
        let listTypes: [NotesSemanticDocument.BlockType] = [.unorderedList, .orderedList, .checklist]

        for listType in listTypes {
            let interiorItem = NoteBlockLayout.metrics(
                for: listType,
                context: NoteBlockLayoutContext(baseFontSize: baseFontSize, nextBlockType: listType)
            )
            let finalItemBeforeParagraph = NoteBlockLayout.metrics(
                for: listType,
                context: NoteBlockLayoutContext(baseFontSize: baseFontSize, nextBlockType: .paragraph)
            )
            let finalItemAtDocumentEnd = NoteBlockLayout.metrics(
                for: listType,
                context: NoteBlockLayoutContext(baseFontSize: baseFontSize)
            )

            XCTAssertEqual(interiorItem.spacingAfter, 0, accuracy: 0.001)
            XCTAssertEqual(finalItemBeforeParagraph.spacingAfter, 4, accuracy: 0.001)
            XCTAssertEqual(finalItemAtDocumentEnd.spacingAfter, 4, accuracy: 0.001)
        }
    }

    func testRenderedListContainerOnlyAddsSpacingAfterFinalItem() throws {
        let baseFontSize: CGFloat = 16
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(
                    type: .unorderedList,
                    children: [
                        .init(type: .listItem, content: [.init(text: "First Item", marks: [])]),
                        .init(type: .listItem, content: [.init(text: "Second Item", marks: [])])
                    ]
                ),
                .paragraph([.init(text: "After list", marks: [])])
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let text = attributed.string as NSString
        let firstItemStyle = try paragraphStyle(
            in: attributed,
            at: text.range(of: "First Item").location
        )
        let secondItemStyle = try paragraphStyle(
            in: attributed,
            at: text.range(of: "Second Item").location
        )

        XCTAssertEqual(firstItemStyle.paragraphSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(secondItemStyle.paragraphSpacing, 4, accuracy: 0.001)
    }

    func testNoteBlockLayoutMetricsApplyCodeBlockAdjacencySpacingToNeighborBlocks() throws {
        let baseFontSize: CGFloat = 16

        let beforeCodeBlock = NoteBlockLayout.metrics(
            for: .paragraph,
            context: NoteBlockLayoutContext(baseFontSize: baseFontSize, nextBlockType: .codeBlock)
        )
        let afterCodeBlock = NoteBlockLayout.metrics(
            for: .paragraph,
            context: NoteBlockLayoutContext(baseFontSize: baseFontSize, previousBlockType: .codeBlock)
        )
        let codeBlock = NoteBlockLayout.metrics(
            for: .codeBlock,
            context: NoteBlockLayoutContext(
                baseFontSize: baseFontSize,
                previousBlockType: .paragraph,
                nextBlockType: .paragraph
            )
        )

        XCTAssertEqual(
            beforeCodeBlock.spacingAfter,
            4 + NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize),
            accuracy: 0.001
        )
        XCTAssertEqual(
            afterCodeBlock.spacingBefore,
            NoteTextParagraphMetrics.codeBlockPaddingAfter(baseFontSize: baseFontSize),
            accuracy: 0.001
        )
        XCTAssertEqual(codeBlock.spacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(codeBlock.spacingAfter, 0, accuracy: 0.001)
    }

    func testNoteBlockLayoutParagraphStyleUsesResolvedMetrics() throws {
        let baseFontSize: CGFloat = 16

        let orderedList = NoteBlockLayout.paragraphStyle(
            for: .orderedList,
            context: NoteBlockLayoutContext(baseFontSize: baseFontSize)
        )
        let codeBlock = NoteBlockLayout.paragraphStyle(
            for: .codeBlock,
            context: NoteBlockLayoutContext(baseFontSize: baseFontSize)
        )
        let paragraphBeforeCode = NoteBlockLayout.paragraphStyle(
            for: .paragraph,
            context: NoteBlockLayoutContext(baseFontSize: baseFontSize, nextBlockType: .codeBlock)
        )

        XCTAssertEqual(orderedList.firstLineHeadIndent, baseFontSize, accuracy: 0.001)
        XCTAssertEqual(orderedList.headIndent, baseFontSize * 2.5, accuracy: 0.001)
        XCTAssertEqual(codeBlock.headIndent, baseFontSize * 0.75, accuracy: 0.001)
        XCTAssertEqual(codeBlock.tailIndent, -(baseFontSize * 0.75), accuracy: 0.001)
        XCTAssertEqual(
            paragraphBeforeCode.paragraphSpacing,
            4 + NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize),
            accuracy: 0.001
        )
    }

    func testOrderedListParagraphMetricsUseHangingIndentAndTabStop() throws {
        let baseFontSize: CGFloat = 16
        let expectedIndent = NoteTextParagraphMetrics.orderedListContentIndent(
            baseFontSize: baseFontSize
        )
        let expectedMarkerIndent = NoteTextParagraphMetrics.orderedListMarkerIndent(
            baseFontSize: baseFontSize
        )
        let style = NoteTextParagraphMetrics.paragraphStyle(
            for: .orderedList,
            baseFontSize: baseFontSize,
            headIndent: expectedIndent,
            firstLineHeadIndent: expectedMarkerIndent,
            tabStops: [
                NSTextTab(textAlignment: .left, location: expectedIndent)
            ],
            defaultTabInterval: expectedIndent
        )

        XCTAssertEqual(style.firstLineHeadIndent, expectedMarkerIndent, accuracy: 0.001)
        XCTAssertEqual(style.headIndent, expectedIndent, accuracy: 0.001)
        XCTAssertEqual(style.tabStops.count, 1)
        XCTAssertEqual(style.tabStops.first?.location ?? 0, expectedIndent, accuracy: 0.001)
        XCTAssertEqual(style.defaultTabInterval, expectedIndent, accuracy: 0.001)
    }

    #if os(macOS)
    func testMakePlatformAttributedContentUsesSecondaryLabelColorForBlockquotesOnMacOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted", marks: [])])
                    ]
                )
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let prefixColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        let contentColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
        )

        XCTAssertEqual(prefixColor, .secondaryLabelColor)
        XCTAssertEqual(contentColor, .secondaryLabelColor)
    }

    func testMountedReadViewBlockquoteRuleRectsAlignWithPrefixOnMacOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .paragraph,
                    content: [.init(text: "Before quote", marks: [])]
                ),
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted text", marks: [])])
                    ]
                ),
                .init(
                    type: .paragraph,
                    content: [.init(text: "After quote", marks: [])]
                )
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        let quoteRange = (try XCTUnwrap(textView.textStorage).string as NSString).range(of: "Quoted text")
        XCTAssertNotEqual(quoteRange.location, NSNotFound)
        let quoteGlyphRect = try glyphRect(in: textView, characterIndex: quoteRange.location)
        let quoteRect = quoteGlyphRect.offsetBy(
            dx: textView.textContainerInset.width,
            dy: textView.textContainerInset.height
        )
        let ruleRects = NoteTextBlockquoteDecorationLayout.ruleRects(
            in: try XCTUnwrap(textView.textStorage),
            layoutManager: try XCTUnwrap(textView.layoutManager),
            textContainer: try XCTUnwrap(textView.textContainer),
            textContainerInset: textView.textContainerInset
        )
        let ruleRect = try XCTUnwrap(ruleRects.first)

        XCTAssertLessThan(
            ruleRect.maxX,
            quoteRect.minX,
            "Expected rule rect \(ruleRect.debugDescription) to sit left of quote rect \(quoteRect.debugDescription)"
        )
        XCTAssertGreaterThan(
            ruleRect.maxX,
            quoteRect.minX - 16,
            "Expected rule rect \(ruleRect.debugDescription) to remain visually adjacent to quote rect \(quoteRect.debugDescription)"
        )
        XCTAssertEqual(
            ruleRect.midY,
            quoteRect.midY,
            accuracy: 2,
            "Expected rule rect \(ruleRect.debugDescription) to align vertically with quote rect \(quoteRect.debugDescription)"
        )
        XCTAssertLessThanOrEqual(
            ruleRect.height,
            quoteRect.height + 2,
            "Expected rule rect \(ruleRect.debugDescription) to avoid covering blockquote paragraph margin"
        )
    }
    #endif

    #if os(iOS)
    #endif
}
