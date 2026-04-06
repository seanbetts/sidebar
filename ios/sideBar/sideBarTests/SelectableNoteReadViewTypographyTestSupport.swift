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
extension SelectableNoteReadViewTypographyTests {
    func fontPointSize(in attributed: NSAttributedString, at location: Int) throws -> CGFloat {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return try XCTUnwrap(font).pointSize
    }

    func fontHasBoldTrait(in attributed: NSAttributedString, at location: Int) throws -> Bool {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return fontHasBoldTrait(try XCTUnwrap(font))
    }

    func fontWeight(in attributed: NSAttributedString, at location: Int) throws -> CGFloat {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return fontWeight(try XCTUnwrap(font))
    }

    func fontHasBoldTrait(_ font: NotePlatformFont) -> Bool {
        #if os(iOS)
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #elseif os(macOS)
        let traitMask = NSFontManager.shared.traits(of: font)
        return font.fontDescriptor.symbolicTraits.contains(.bold) || traitMask.contains(.boldFontMask)
        #endif
    }

    func fontWeight(_ font: NotePlatformFont) -> CGFloat {
        #if os(iOS)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? UIFont.Weight.regular.rawValue
        #elseif os(macOS)
        return CGFloat(NSFontManager.shared.weight(of: font))
        #endif
    }

    #if os(iOS)
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
        let alpha = CGFloat(bytes?[offset + 3] ?? 0) / 255
        guard alpha > 0 else { return UIColor(red: 0, green: 0, blue: 0, alpha: 0) }

        return UIColor(
            red: (CGFloat(bytes?[offset] ?? 0) / 255) / alpha,
            green: (CGFloat(bytes?[offset + 1] ?? 0) / 255) / alpha,
            blue: (CGFloat(bytes?[offset + 2] ?? 0) / 255) / alpha,
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

    func contentGlyphRect(
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
}
