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
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted text", marks: [])])
                    ]
                )
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        let prefixGlyphRect = try glyphRect(in: textView, characterIndex: 0)
        let prefixRect = prefixGlyphRect.offsetBy(
            dx: textView.textContainerInset.width,
            dy: textView.textContainerInset.height
        )
        let ruleRect = try XCTUnwrap(
            NoteTextBlockquoteDecorationLayout.ruleRects(
                in: try XCTUnwrap(textView.textStorage),
                layoutManager: try XCTUnwrap(textView.layoutManager),
                textContainer: try XCTUnwrap(textView.textContainer),
                textContainerInset: textView.textContainerInset
            ).first
        )

        XCTAssertLessThan(
            ruleRect.maxX,
            prefixRect.minX,
            "Expected rule rect \(ruleRect.debugDescription) to sit left of prefix rect \(prefixRect.debugDescription)"
        )
        XCTAssertGreaterThan(
            ruleRect.maxX,
            prefixRect.minX - 16,
            "Expected rule rect \(ruleRect.debugDescription) to remain visually adjacent to prefix rect \(prefixRect.debugDescription)"
        )
        XCTAssertEqual(
            ruleRect.midY,
            prefixRect.midY,
            accuracy: 2,
            "Expected rule rect \(ruleRect.debugDescription) to align vertically with prefix rect \(prefixRect.debugDescription)"
        )
    }
    #endif

    #if os(iOS)
    func testMakePlatformAttributedContentUsesSecondaryLabelColorForBlockquotesOnIOS() throws {
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
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let contentColor = try XCTUnwrap(
            attributed.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? UIColor
        )
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            prefixColor.resolvedColor(with: darkTraits),
            UIColor.secondaryLabel.resolvedColor(with: darkTraits)
        )
        XCTAssertEqual(
            contentColor.resolvedColor(with: darkTraits),
            UIColor.secondaryLabel.resolvedColor(with: darkTraits)
        )
    }

    func testMountedReadViewDrawsBlockquoteRuleOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted text", marks: [])])
                    ]
                )
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        let prefixRect = try characterRect(in: textView, characterIndex: 0)
        let samplePoint = CGPoint(
            x: max(1, prefixRect.minX - 7),
            y: prefixRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: textView.traitCollection),
            UIColor.separator.resolvedColor(with: textView.traitCollection),
            tolerance: 0.08
        )
    }

    func testDetachedBlockquoteRuleRectsAlignWithMountedPrefixOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .blockquote,
                    children: [
                        .paragraph([.init(text: "Quoted text", marks: [])])
                    ]
                )
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        let prefixRect = try characterRect(in: textView, characterIndex: 0)
        let ruleRect = try XCTUnwrap(
            NoteTextBlockquoteDecorationLayout.detachedRuleRects(
                in: textView.attributedText,
                containerWidth: textView.bounds.width,
                textContainerInset: CGSize(
                    width: textView.textContainerInset.left,
                    height: textView.textContainerInset.top
                )
            ).first
        )

        XCTAssertLessThan(
            ruleRect.maxX,
            prefixRect.minX,
            "Expected rule rect \(ruleRect.debugDescription) to sit left of prefix rect \(prefixRect.debugDescription)"
        )
        XCTAssertGreaterThan(
            ruleRect.maxX,
            prefixRect.minX - 16,
            "Expected rule rect \(ruleRect.debugDescription) to remain visually adjacent to prefix rect \(prefixRect.debugDescription)"
        )
        XCTAssertEqual(
            ruleRect.midY,
            prefixRect.midY,
            accuracy: 2,
            "Expected rule rect \(ruleRect.debugDescription) to align vertically with prefix rect \(prefixRect.debugDescription)"
        )
    }

    func testMakePlatformAttributedContentUsesInlineCodeBackgroundOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(
                    type: .title,
                    content: [.init(text: "code", marks: [.inlineCode])]
                )
            ]
        )
        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
        let color = try XCTUnwrap(
            attributed.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor
        )
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        XCTAssertEqual(
            color.resolvedColor(with: darkTraits),
            UIColor.secondarySystemFill.resolvedColor(with: darkTraits)
        )
    }

    func testMountedReadViewDrawsCustomCodeBlockBackgroundOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])])
            ]
        )
        let textView = try makeReadTextView(document: document, frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let codeBlockAttributed = SelectableNoteReadView.makePlatformAttributedContent(from: document, baseFontSize: 16)
        XCTAssertNil(codeBlockAttributed.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try characterRect(in: textView, characterIndex: 9)
        let shortLineRect = try characterRect(in: textView, characterIndex: 12)
        let samplePoint = CGPoint(
            x: shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: shortLineRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: textView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: textView.traitCollection),
            tolerance: 0.05
        )
    }

    func testMountedReadViewDoesNotDrawCodeBlockBackgroundAbovePrecedingParagraphOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .paragraph([.init(text: "Before it:", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let name: String\nprint(name)", marks: [])]),
                .paragraph([.init(text: "After it", marks: [])])
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )
        let beforeRect = try characterRect(in: textView, characterIndex: 0)
        let samplePoint = CGPoint(
            x: min(beforeRect.maxX + 80, textView.bounds.maxX - 10),
            y: beforeRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyNotEqual(
            sampledColor.resolvedColor(with: textView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: textView.traitCollection),
            tolerance: 0.05
        )
    }

    func testMountedReadViewMovesCodeBlockBackgroundWithContentDuringScrollOnIOS() throws {
        let document = NotesSemanticDocument(
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])]),
                .paragraph([.init(text: String(repeating: "Trailing paragraph text. ", count: 40), marks: [])])
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        textView.setNeedsDisplay()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let codeBlockRect = try XCTUnwrap(
            NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
                in: textView.attributedText,
                containerWidth: textView.bounds.width,
                textContainerInset: CGSize(
                    width: textView.textContainerInset.left,
                    height: textView.textContainerInset.top
                )
            ).first
        )
        let samplePoint = CGPoint(
            x: min(codeBlockRect.maxX - 10, textView.bounds.maxX - 10),
            y: codeBlockRect.midY
        )
        let initialColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        textView.setContentOffset(CGPoint(x: 0, y: 160), animated: false)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let scrolledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            initialColor.resolvedColor(with: textView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: textView.traitCollection),
            tolerance: 0.05
        )
        assertColorsApproximatelyNotEqual(
            scrolledColor.resolvedColor(with: textView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: textView.traitCollection),
            tolerance: 0.05
        )
    }

    func testDetachedDecorationRectsMatchMountedReadLayoutForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 420, height: 900)
        )
        let liveCodeRects = NoteTextCodeBlockBackgroundLayout.blockRects(
            in: textView.attributedText,
            layoutManager: textView.layoutManager,
            textContainer: textView.textContainer,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )
        let detachedCodeRects = NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
            in: textView.attributedText,
            containerWidth: textView.bounds.width,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )
        let liveRuleRects = NoteTextBlockquoteDecorationLayout.ruleRects(
            in: textView.attributedText,
            layoutManager: textView.layoutManager,
            textContainer: textView.textContainer,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )
        let detachedRuleRects = NoteTextBlockquoteDecorationLayout.detachedRuleRects(
            in: textView.attributedText,
            containerWidth: textView.bounds.width,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )

        XCTAssertEqual(detachedCodeRects.count, liveCodeRects.count)
        XCTAssertEqual(detachedRuleRects.count, liveRuleRects.count)

        for (detachedRect, liveRect) in zip(detachedCodeRects, liveCodeRects) {
            XCTAssertEqual(detachedRect.minY, liveRect.minY, accuracy: 1)
            XCTAssertEqual(detachedRect.maxY, liveRect.maxY, accuracy: 1)
        }

        for (detachedRect, liveRect) in zip(detachedRuleRects, liveRuleRects) {
            XCTAssertEqual(detachedRect.minY, liveRect.minY, accuracy: 1)
            XCTAssertEqual(detachedRect.maxY, liveRect.maxY, accuracy: 1)
        }
    }

    func testMountedReadViewKeepsCodeBlockBackgroundAlignedAfterScrollForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 420, height: 420)
        )
        let plainText = textView.attributedText.string as NSString
        let firstLineRange = plainText.range(of: "function greet(name) {")
        let secondLineRange = plainText.range(of: "console.log('Hello, ${name}!');")
        XCTAssertNotEqual(firstLineRange.location, NSNotFound)
        XCTAssertNotEqual(secondLineRange.location, NSNotFound)

        let firstLineRect = try contentGlyphRect(in: textView, characterIndex: firstLineRange.location)
        let secondLineRect = try contentGlyphRect(
            in: textView,
            characterIndex: secondLineRange.location + secondLineRange.length - 1
        )
        XCTAssertGreaterThan(secondLineRect.maxX - firstLineRect.maxX, 20)

        textView.setContentOffset(
            CGPoint(x: 0, y: max(firstLineRect.minY - 120, 0)),
            animated: false
        )
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let samplePoint = CGPoint(
            x: firstLineRect.maxX + ((secondLineRect.maxX - firstLineRect.maxX) * 0.5),
            y: firstLineRect.midY - textView.contentOffset.y
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: textView.traitCollection),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: textView.traitCollection),
            tolerance: 0.05
        )
    }

    func testMountedReadViewKeepsBlockquoteRuleAlignedAfterScrollForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 420, height: 420)
        )
        let plainText = textView.attributedText.string as NSString
        let quoteRange = plainText.range(of: "This is a blockquote.")
        XCTAssertNotEqual(quoteRange.location, NSNotFound)

        let quoteRect = try contentGlyphRect(in: textView, characterIndex: quoteRange.location)
        textView.setContentOffset(
            CGPoint(x: 0, y: max(quoteRect.minY - 120, 0)),
            animated: false
        )
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let samplePoint = CGPoint(
            x: max(1, quoteRect.minX - 7),
            y: quoteRect.midY - textView.contentOffset.y
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: textView.traitCollection),
            UIColor.separator.resolvedColor(with: textView.traitCollection),
            tolerance: 0.08
        )
    }

    func testMakePlatformAttributedContentPreservesContextualParagraphSpacingAroundCodeBlocksOnIOS() throws {
        let baseFontSize: CGFloat = 16
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1", marks: [])]),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )

        let attributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )

        let beforeStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let codeBlockStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 7, effectiveRange: nil) as? NSParagraphStyle
        )
        let afterStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 17, effectiveRange: nil) as? NSParagraphStyle
        )
        let paddingBefore = NoteTextParagraphMetrics.codeBlockPaddingBefore(baseFontSize: baseFontSize)
        let paddingAfter = NoteTextParagraphMetrics.codeBlockPaddingAfter(baseFontSize: baseFontSize)

        XCTAssertEqual(beforeStyle.paragraphSpacing, 4 + paddingBefore, accuracy: 0.001)
        XCTAssertEqual(codeBlockStyle.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(codeBlockStyle.paragraphSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(afterStyle.paragraphSpacingBefore, paddingAfter, accuracy: 0.001)
    }
    #endif

    private func fontPointSize(in attributed: NSAttributedString, at location: Int) throws -> CGFloat {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return try XCTUnwrap(font).pointSize
    }

    private func fontHasBoldTrait(in attributed: NSAttributedString, at location: Int) throws -> Bool {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return fontHasBoldTrait(try XCTUnwrap(font))
    }

    private func fontWeight(in attributed: NSAttributedString, at location: Int) throws -> CGFloat {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return fontWeight(try XCTUnwrap(font))
    }

    private func fontHasBoldTrait(_ font: NotePlatformFont) -> Bool {
        #if os(iOS)
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #elseif os(macOS)
        let traitMask = NSFontManager.shared.traits(of: font)
        return font.fontDescriptor.symbolicTraits.contains(.bold) || traitMask.contains(.boldFontMask)
        #endif
    }

    private func fontWeight(_ font: NotePlatformFont) -> CGFloat {
        #if os(iOS)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? UIFont.Weight.regular.rawValue
        #elseif os(macOS)
        return CGFloat(NSFontManager.shared.weight(of: font))
        #endif
    }

    #if os(iOS)
    private func samplePixelColor(
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

    private func assertColorsApproximatelyEqual(
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

    private func assertColorsApproximatelyNotEqual(
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

        let redDelta = abs(actualRed - expectedRed)
        let greenDelta = abs(actualGreen - expectedGreen)
        let blueDelta = abs(actualBlue - expectedBlue)
        let alphaDelta = abs(actualAlpha - expectedAlpha)
        let matchesExpectedWithinTolerance = redDelta <= tolerance &&
            greenDelta <= tolerance &&
            blueDelta <= tolerance &&
            alphaDelta <= tolerance

        XCTAssertFalse(matchesExpectedWithinTolerance, file: file, line: line)
    }

    private func contentGlyphRect(
        in textView: UITextView,
        characterIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGRect {
        let attributedText = textView.attributedText ?? NSAttributedString()
        guard characterIndex >= 0, characterIndex < attributedText.length else {
            XCTFail("Character index out of bounds", file: file, line: line)
            return .zero
        }

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        textContainer.size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).offsetBy(
            dx: textView.textContainerInset.left,
            dy: textView.textContainerInset.top
        )
    }
    #endif

    private func complexDecorationDocument() -> NotesSemanticDocument {
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
}
