import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadViewLinkTests: XCTestCase {
    func testMakeAttributedContentPreservesFormattingAndUsesStoredLinkSemantics() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([
                    .init(text: "Visit ", marks: []),
                    .init(
                        text: "Example docs",
                        marks: [.bold],
                        link: .init(url: "https://example.com")
                    ),
                    .init(text: " today", marks: [.underline])
                ])
            ]
        )

        let attributed = SelectableNoteReadView.makeAttributedContent(
            from: document,
            baseFontSize: 18
        )

        XCTAssertEqual(String(attributed.characters), "Visit Example docs today")

        let linkStart = attributed.index(attributed.startIndex, offsetByCharacters: 6)
        let linkEnd = attributed.index(linkStart, offsetByCharacters: 12)
        XCTAssertTrue(noteRangeHasBoldTrait(attributed, range: linkStart..<linkEnd))
        XCTAssertTrue(noteRangeIsUnderlined(attributed, range: linkEnd..<attributed.endIndex))

        let bridged = NSAttributedString(attributed)
        let expectedURL = try XCTUnwrap(URL(string: "https://example.com"))
        let linkValue = bridged.attribute(
            NSAttributedString.Key.link,
            at: 7,
            effectiveRange: nil
        ) as? URL
        XCTAssertEqual(linkValue, expectedURL)
    }
}
