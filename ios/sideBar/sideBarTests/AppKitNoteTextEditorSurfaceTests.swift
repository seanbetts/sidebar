#if os(macOS)
import AppKit
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AppKitNoteTextEditorSurfaceTests: NotesDetailViewHostingTestCase {
    func testMountedAppKitEditorUsesSharedTypographyAndParagraphMetrics() throws {
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])]),
                .init(type: .subheading, content: [.init(text: "Subheading", marks: [])]),
                .paragraph([.init(text: "Body", marks: [])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: baseFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 280)
        )

        XCTAssertEqual(textView.string, "Title\nHeading\nSubheading\nBody")

        let titleFont = try fontAttribute(in: textView, at: 0)
        let headingFont = try fontAttribute(in: textView, at: 6)
        let subheadingFont = try fontAttribute(in: textView, at: 14)
        let bodyFont = try fontAttribute(in: textView, at: 25)

        XCTAssertEqual(
            titleFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .title, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            headingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .heading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            subheadingFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .subheading, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertEqual(
            bodyFont.pointSize,
            NoteTextStyleTypography.platformFont(for: .body, baseFontSize: baseFontSize).pointSize,
            accuracy: 0.001
        )
        XCTAssertTrue(notePlatformFontTraits(from: titleFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: headingFont).bold)
        XCTAssertTrue(notePlatformFontTraits(from: subheadingFont).bold)
        XCTAssertFalse(notePlatformFontTraits(from: bodyFont).bold)

        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .title, baseFontSize: baseFontSize),
            at: 0
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .heading, baseFontSize: baseFontSize),
            at: 6
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .subheading, baseFontSize: baseFontSize),
            at: 14
        )
        try assertParagraphStyle(
            in: textView,
            matches: NoteTextParagraphMetrics.paragraphStyle(for: .paragraph, baseFontSize: baseFontSize),
            at: 25
        )
    }

    func testMountedAppKitEditorUsesInlineCodeBackgroundAndMonospacedFont() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "code", marks: [.inlineCode])])
            ]
        )
        let textView = try mountEditorTextView(
            document: document,
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        let font = try fontAttribute(in: textView, at: 0)
        let backgroundColor = try backgroundColorAttribute(in: textView, at: 0)

        XCTAssertTrue(notePlatformFontTraits(from: font).monospaced)
        XCTAssertEqual(backgroundColor, NoteTextAppearance.inlineCodeBackgroundColor)
    }

    func testMountedAppKitEditorUsesSecondaryLabelCaretTint() throws {
        let textView = try mountEditorTextView(
            document: NotesSemanticDocumentProjection.document(fromPlainText: "Hello"),
            baseFontSize: NoteTextTypography.defaultBodyFontSize,
            frame: NSRect(x: 0, y: 0, width: 420, height: 180)
        )

        XCTAssertEqual(textView.insertionPointColor, .secondaryLabelColor)
    }
}

private func fontAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSFont {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
        file: file,
        line: line
    )
}

private func backgroundColorAttribute(
    in textView: NSTextView,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> NSColor {
    guard textView.string.utf16.count > location else {
        XCTFail("Expected text length > \(location), got \(textView.string.utf16.count)", file: file, line: line)
        throw AppKitNoteTextEditorSurfaceTestError.missingAttribute
    }

    return try XCTUnwrap(
        textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor,
        file: file,
        line: line
    )
}

private func assertParagraphStyle(
    in textView: NSTextView,
    matches expected: NSParagraphStyle,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actual = try XCTUnwrap(
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
        file: file,
        line: line
    )
    XCTAssertEqual(actual.lineSpacing, expected.lineSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacingBefore, expected.paragraphSpacingBefore, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.paragraphSpacing, expected.paragraphSpacing, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.headIndent, expected.headIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.firstLineHeadIndent, expected.firstLineHeadIndent, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.tailIndent, expected.tailIndent, accuracy: 0.001, file: file, line: line)
}

private enum AppKitNoteTextEditorSurfaceTestError: Error {
    case missingAttribute
}
#endif
