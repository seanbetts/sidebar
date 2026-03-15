import XCTest
import SwiftUI
@testable import sideBar

#if os(iOS)
@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NotesEditorFallbackSurfaceTests: XCTestCase {
    func testConstrainedEditorDocumentUsesLineOwnedBlockFallbackForUnmarkedRunsOnIOS() throws {
        let baseFontSize = NoteTextTypography.defaultBodyFontSize
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .init(type: .title, content: [.init(text: "Title", marks: [])]),
                .init(type: .heading, content: [.init(text: "Heading", marks: [])])
            ]
        )
        var attributed = NotesAttributedDocumentCodec.attributedString(
            from: document,
            baseFontSize: baseFontSize
        )
        let headingStart = attributed.index(attributed.startIndex, offsetByCharacters: 6)
        let headingEnd = attributed.index(headingStart, offsetByCharacters: 7)
        attributed[headingStart..<headingEnd].noteBlock = nil

        let constrained = constrainedEditorDocument(
            from: attributed,
            baseFontSize: baseFontSize
        )
        let bridged = (try? NSAttributedString(constrained, including: \.noteTextEditor))
            ?? NSAttributedString(constrained)
        let expectedHeadingStyle = NoteTextParagraphMetrics.paragraphStyle(
            for: .heading,
            baseFontSize: baseFontSize
        )

        XCTAssertEqual(
            bridged.attribute(.paragraphStyle, at: 6, effectiveRange: nil) as? NSParagraphStyle,
            expectedHeadingStyle
        )
        XCTAssertEqual(NotesAttributedDocumentCodec.document(from: constrained), document)
    }
}

@MainActor
private func constrainedEditorDocument(
    from attributed: AttributedString,
    baseFontSize: CGFloat
) -> AttributedString {
    var constrained = attributed
    NoteTextFormattingDefinition(baseFontSize: baseFontSize).constrainDocument(&constrained)
    return constrained
}
#endif
