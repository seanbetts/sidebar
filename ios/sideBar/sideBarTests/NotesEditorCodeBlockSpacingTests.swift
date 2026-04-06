#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorCodeBlockSpacingTests: XCTestCase {
    private let expectedCodeBlockVerticalPadding = NoteTextAppearance.codeBlockVerticalPadding

    func testMountedUIKitEditorSnapshotCapturesInjectedSubviewOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [.paragraph([.init(text: "Probe", marks: [])])]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize)
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            width: 240,
            height: 160
        )
        let renderView = try XCTUnwrap(textView.superview)
        let probeColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        let probeView = UIView(frame: CGRect(x: 12, y: 12, width: 40, height: 40))
        probeView.backgroundColor = probeColor
        probeView.isUserInteractionEnabled = false
        textView.addSubview(probeView)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        renderView.setNeedsLayout()
        renderView.layoutIfNeeded()

        let sampledColor = try XCTUnwrap(samplePixelColor(in: renderView, at: CGPoint(x: 20, y: 20)))
        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: renderView.traitCollection),
            probeColor.resolvedColor(with: renderView.traitCollection),
            tolerance: 0.08
        )
    }

    func testMountedUIKitEditorDrawsCustomCodeBlockBackgroundOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .codeBlock, content: [.init(text: "abcdefghij\nab", marks: [])])
            ]
        )
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize)
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            width: 420,
            height: 180
        )
        let renderView = try XCTUnwrap(textView.superview)

        XCTAssertNil(textView.attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try glyphRect(in: textView, characterIndex: 9)
        let shortLineRect = try glyphRect(in: textView, characterIndex: 12)
        let samplePoint = CGPoint(
            x: textView.textContainerInset.left + shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: textView.textContainerInset.top + shortLineRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: renderView, at: samplePoint))
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: darkTraits),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: darkTraits),
            tolerance: 0.05
        )
    }

    func testMountedUIKitEditorDoesNotDrawCodeBlockBackgroundAbovePrecedingParagraphOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before it:", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let name: String\nprint(name)", marks: [])]),
                .paragraph([.init(text: "After it", marks: [])])
            ]
        )
        let textView = try makeEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )
        let beforeRect = try glyphRect(in: textView, characterIndex: 0)
        let samplePoint = CGPoint(
            x: min(textView.textContainerInset.left + beforeRect.maxX + 80, textView.bounds.maxX - 10),
            y: textView.textContainerInset.top + beforeRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        assertColorsApproximatelyNotEqual(
            sampledColor.resolvedColor(with: darkTraits),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: darkTraits),
            tolerance: 0.05
        )
    }

    func testUIKitCodeBlockBackgroundLayoutUsesFixedVerticalPaddingAroundContentOnIOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before", marks: [])]),
                .init(type: .codeBlock, content: [.init(text: "let x = 1\nprint(x)", marks: [])]),
                .paragraph([.init(text: "After", marks: [])])
            ]
        )
        let textView = try makeEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )

        let blockRect = try XCTUnwrap(
            NoteTextCodeBlockBackgroundLayout.blockRects(
                in: textView.attributedText,
                layoutManager: textView.layoutManager,
                textContainer: textView.textContainer,
                textContainerInset: CGSize(
                    width: textView.textContainerInset.left,
                    height: textView.textContainerInset.top
                )
            ).first
        )
        let contentRect = try codeBlockContentLineFragmentUnion(in: textView)

        XCTAssertEqual(
            contentRect.minY - blockRect.minY,
            expectedCodeBlockVerticalPadding,
            accuracy: 1
        )
        XCTAssertEqual(
            blockRect.maxY - contentRect.maxY,
            expectedCodeBlockVerticalPadding,
            accuracy: 1
        )
    }

    func testReadAndEditorSurfacesAddVerticalPaddingAroundCodeBlocksOnIOS() throws {
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

        let readAttributed = SelectableNoteReadView.makePlatformAttributedContent(
            from: document,
            baseFontSize: baseFontSize
        )
        let readTextView = makeReadTextView(
            attributedContent: readAttributed,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )
        let editorTextView = try makeEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: CGRect(x: 0, y: 0, width: 420, height: 240)
        )

        let readGapAbove = try lineGap(in: readTextView, fromCharacterAt: 0, toCharacterAt: 7)
        let readInternalGap = try lineGap(in: readTextView, fromCharacterAt: 7, toCharacterAt: 17)
        let readGapBelow = try lineGap(in: readTextView, fromCharacterAt: 17, toCharacterAt: 26)
        let editorGapAbove = try lineGap(in: editorTextView, fromCharacterAt: 0, toCharacterAt: 7)
        let editorInternalGap = try lineGap(in: editorTextView, fromCharacterAt: 7, toCharacterAt: 17)
        let editorGapBelow = try lineGap(in: editorTextView, fromCharacterAt: 17, toCharacterAt: 26)

        XCTAssertGreaterThan(readGapAbove - readInternalGap, expectedGapAboveDelta - 0.75)
        XCTAssertGreaterThan(readGapBelow - readInternalGap, expectedGapBelowDelta - 0.75)
        XCTAssertGreaterThan(readGapBelow - readGapAbove, 3)
        XCTAssertGreaterThan(editorGapAbove - editorInternalGap, expectedGapAboveDelta - 0.75)
        XCTAssertGreaterThan(editorGapBelow - editorInternalGap, expectedGapBelowDelta - 0.75)
        XCTAssertGreaterThan(editorGapBelow - editorGapAbove, 3)
    }

    func testDetachedCodeBlockRectsMatchMountedEditorLayoutForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize)
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            width: 420,
            height: 900
        )
        let liveRects = NoteTextCodeBlockBackgroundLayout.blockRects(
            in: textView.attributedText,
            layoutManager: textView.layoutManager,
            textContainer: textView.textContainer,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )
        let detachedRects = NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
            in: textView.attributedText,
            containerWidth: textView.bounds.width,
            textContainerInset: CGSize(
                width: textView.textContainerInset.left,
                height: textView.textContainerInset.top
            )
        )

        XCTAssertEqual(detachedRects.count, liveRects.count)

        for (detachedRect, liveRect) in zip(detachedRects, liveRects) {
            XCTAssertEqual(detachedRect.minY, liveRect.minY, accuracy: 1)
            XCTAssertEqual(detachedRect.maxY, liveRect.maxY, accuracy: 1)
        }
    }

    func testMountedUIKitEditorKeepsCodeBlockBackgroundAlignedAfterScrollForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize)
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            width: 420,
            height: 420
        )
        let renderView = try XCTUnwrap(textView.superview)
        let plainText = textView.attributedText.string as NSString
        let firstLineRange = plainText.range(of: "function greet(name) {")
        let secondLineRange = plainText.range(of: "console.log('Hello, ${name}!');")
        XCTAssertNotEqual(firstLineRange.location, NSNotFound)
        XCTAssertNotEqual(secondLineRange.location, NSNotFound)

        let firstLineRect = try glyphRect(in: textView, characterIndex: firstLineRange.location).offsetBy(
            dx: textView.textContainerInset.left,
            dy: textView.textContainerInset.top
        )
        let secondLineRect = try glyphRect(
            in: textView,
            characterIndex: secondLineRange.location + secondLineRange.length - 1
        ).offsetBy(
            dx: textView.textContainerInset.left,
            dy: textView.textContainerInset.top
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
        let sampledColor = try XCTUnwrap(samplePixelColor(in: renderView, at: samplePoint))
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: darkTraits),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: darkTraits),
            tolerance: 0.05
        )
    }

    func testMountedUIKitEditorKeepsBlockquoteRuleAlignedAfterScrollForComplexDocumentOnIOS() throws {
        let document = complexDecorationDocument()
        let viewModel = NativeNoteEditorViewModel()
        viewModel.setBaseFontSize(NoteTextTypography.defaultBodyFontSize)
        viewModel.loadDocument(
            canonicalContent: try XCTUnwrap(NotesSemanticDocumentCodec.encode(document)),
            plainText: NotesSemanticDocumentProjection.plainText(from: document)
        )
        let textView = try mountTextView(
            viewModel: viewModel,
            formattingBarConfiguration: .disabled,
            width: 420,
            height: 420
        )
        let renderView = try XCTUnwrap(textView.superview)
        let plainText = textView.attributedText.string as NSString
        let quoteRange = plainText.range(of: "This is a blockquote.")
        XCTAssertNotEqual(quoteRange.location, NSNotFound)

        let quoteRect = try glyphRect(in: textView, characterIndex: quoteRange.location).offsetBy(
            dx: textView.textContainerInset.left,
            dy: textView.textContainerInset.top
        )
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
        let sampledColor = try XCTUnwrap(samplePixelColor(in: renderView, at: samplePoint))

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: renderView.traitCollection),
            UIColor.separator.resolvedColor(with: renderView.traitCollection),
            tolerance: 0.08
        )
    }
}
#endif
