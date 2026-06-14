#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorCodeBlockSpacingTests {
    func lineGap(
        in textView: UITextView,
        fromCharacterAt firstIndex: Int,
        toCharacterAt secondIndex: Int
    ) throws -> CGFloat {
        let firstRect = try glyphRect(in: textView, characterIndex: firstIndex)
        let secondRect = try glyphRect(in: textView, characterIndex: secondIndex)
        return secondRect.minY - firstRect.maxY
    }

    func glyphRect(
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

    func codeBlockContentLineFragmentUnion(
        in textView: UITextView
    ) throws -> CGRect {
        let blockKey = NSAttributedString.Key(NoteTextBlockAttribute.name)
        let boundaryKey = NSAttributedString.Key(NoteTextStructuralBoundaryAttribute.name)
        let attributedText = try XCTUnwrap(textView.attributedText)
        let fullRange = NSRange(location: 0, length: attributedText.length)

        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        textContainer.size = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        var contentRect: CGRect?
        attributedText.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard range.length > 0,
                  let rawBlock = attributes[blockKey] as? NSString,
                  rawBlock as String == NotesSemanticDocument.BlockType.codeBlock.rawValue,
                  (attributes[boundaryKey] as? NSNumber)?.boolValue != true else {
                return
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                let rect = usedRect.offsetBy(
                    dx: textView.textContainerInset.left,
                    dy: textView.textContainerInset.top
                )
                contentRect = contentRect?.union(rect) ?? rect
            }
        }

        return try XCTUnwrap(contentRect)
    }

    func makeReadTextView(
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

    func makeEditorTextView(
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

    func complexDecorationDocument() -> NotesSemanticDocument {
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

    func samplePixelColor(
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
        let byte0 = CGFloat(bytes?[offset] ?? 0) / 255
        let byte1 = CGFloat(bytes?[offset + 1] ?? 0) / 255
        let byte2 = CGFloat(bytes?[offset + 2] ?? 0) / 255
        let byte3 = CGFloat(bytes?[offset + 3] ?? 0) / 255
        let isLittleEndian = cgImage.bitmapInfo.contains(.byteOrder32Little)
        let alphaInfo = cgImage.alphaInfo
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        if isLittleEndian &&
            (alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst) {
            red = byte2
            green = byte1
            blue = byte0
            alpha = byte3
        } else if !isLittleEndian &&
            (alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst) {
            red = byte1
            green = byte2
            blue = byte3
            alpha = byte0
        } else if isLittleEndian &&
            (alphaInfo == .premultipliedLast || alphaInfo == .last || alphaInfo == .noneSkipLast) {
            red = byte1
            green = byte2
            blue = byte3
            alpha = byte0
        } else {
            red = byte0
            green = byte1
            blue = byte2
            alpha = byte3
        }
        guard alpha > 0 else { return UIColor(red: 0, green: 0, blue: 0, alpha: 0) }

        return UIColor(
            red: red / alpha,
            green: green / alpha,
            blue: blue / alpha,
            alpha: alpha
        )
    }

    func assertColorsApproximatelyEqual(
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

    func assertColorsApproximatelyNotEqual(
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

        let differences = [
            abs(actualRed - expectedRed),
            abs(actualGreen - expectedGreen),
            abs(actualBlue - expectedBlue),
            abs(actualAlpha - expectedAlpha)
        ]
        XCTAssertTrue(
            differences.contains(where: { $0 > tolerance }),
            "Expected colors to differ by more than \(tolerance), got \(differences)",
            file: file,
            line: line
        )
    }
}
#endif
