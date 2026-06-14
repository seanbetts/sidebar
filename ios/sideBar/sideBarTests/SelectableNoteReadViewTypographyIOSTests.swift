import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadViewTypographyTests {
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
        let textView = try makeReadTextView(
            document: document,
            frame: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        let codeBlockAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: 16
        )
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
        let marginBefore = NoteTextParagraphMetrics.codeBlockMarginBefore(baseFontSize: baseFontSize)
        let marginAfter = NoteTextParagraphMetrics.codeBlockMarginAfter(baseFontSize: baseFontSize)

        XCTAssertEqual(beforeStyle.paragraphSpacing, 4 + paddingBefore + marginBefore, accuracy: 0.001)
        XCTAssertEqual(codeBlockStyle.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(codeBlockStyle.paragraphSpacing, 0, accuracy: 0.001)
        XCTAssertEqual(afterStyle.paragraphSpacingBefore, paddingAfter + marginAfter, accuracy: 0.001)
    }
    #endif
}
