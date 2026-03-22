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
        XCTAssertEqual(headingStyle.paragraphSpacingBefore, 0, accuracy: 0.001)
        XCTAssertEqual(subheadingStyle.paragraphSpacingBefore, 0, accuracy: 0.001)
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

    #if os(iOS)
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

    func testMountedReadViewDoesNotDrawCustomCodeBlockBackgroundOnIOS() throws {
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
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

        assertColorsApproximatelyNotEqual(
            sampledColor.resolvedColor(with: darkTraits),
            UIColor.secondarySystemFill.resolvedColor(with: darkTraits),
            tolerance: 0.05
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
    #endif
}
