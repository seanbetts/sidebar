import XCTest
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
        XCTAssertEqual(headingFont.pointSize, baseFontSize * 1.5, accuracy: 0.001)
        XCTAssertEqual(subheadingFont.pointSize, baseFontSize * 1.15, accuracy: 0.001)
        XCTAssertEqual(bodyFont.pointSize, baseFontSize * 1.0, accuracy: 0.001)

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
}
