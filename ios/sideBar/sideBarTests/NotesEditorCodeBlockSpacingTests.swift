#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorCodeBlockSpacingTests: XCTestCase {
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

        XCTAssertNil(textView.attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil))

        let longLineRect = try glyphRect(in: textView, characterIndex: 9)
        let shortLineRect = try glyphRect(in: textView, characterIndex: 12)
        let samplePoint = CGPoint(
            x: textView.textContainerInset.left + shortLineRect.maxX + ((longLineRect.maxX - shortLineRect.maxX) * 0.5),
            y: textView.textContainerInset.top + shortLineRect.midY
        )
        let sampledColor = try XCTUnwrap(samplePixelColor(in: textView, at: samplePoint))
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        assertColorsApproximatelyEqual(
            sampledColor.resolvedColor(with: darkTraits),
            NoteTextAppearance.codeBlockBackgroundColor.resolvedColor(with: darkTraits),
            tolerance: 0.05
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
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func lineGap(
    in textView: UITextView,
    fromCharacterAt firstIndex: Int,
    toCharacterAt secondIndex: Int
) throws -> CGFloat {
    let firstRect = try glyphRect(in: textView, characterIndex: firstIndex)
    let secondRect = try glyphRect(in: textView, characterIndex: secondIndex)
    return secondRect.minY - firstRect.maxY
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func glyphRect(
    in textView: UITextView,
    characterIndex: Int
) throws -> CGRect {
    let layoutManager = textView.layoutManager
    let textContainer = textView.textContainer
    textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let glyphRange = layoutManager.glyphRange(
        forCharacterRange: NSRange(location: characterIndex, length: 1),
        actualCharacterRange: nil
    )
    return layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeReadTextView(
    attributedContent: NSAttributedString,
    frame: CGRect
) -> UITextView {
    let textView = UITextView(frame: frame)
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.isScrollEnabled = true
    textView.alwaysBounceVertical = true
    textView.adjustsFontForContentSizeCategory = false
    textView.attributedText = attributedContent
    textView.setNeedsLayout()
    textView.layoutIfNeeded()
    return textView
}

@MainActor
@available(iOS 26.0, macOS 26.0, *)
private func makeEditorTextView(
    document: NotesSemanticDocument,
    baseFontSize: CGFloat,
    frame: CGRect
) throws -> UITextView {
    var constrained = NotesAttributedDocumentCodec.attributedString(
        from: document,
        baseFontSize: baseFontSize
    )
    NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&constrained)

    let textView = UITextView(frame: frame)
    textView.adjustsFontForContentSizeCategory = false
    textView.isEditable = true
    textView.isScrollEnabled = true
    textView.backgroundColor = .clear
    textView.attributedText = NSAttributedString(constrained)
    textView.setNeedsLayout()
    textView.layoutIfNeeded()
    return textView
}

@MainActor
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

@MainActor
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
#endif
