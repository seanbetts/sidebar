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
    }

    private func fontPointSize(in attributed: NSAttributedString, at location: Int) throws -> CGFloat {
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NotePlatformFont
        return try XCTUnwrap(font).pointSize
    }
}
