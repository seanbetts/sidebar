import XCTest
#if os(macOS)
import AppKit
#endif
@testable import sideBar

#if os(macOS)
@MainActor
@available(macOS 26.0, *)
final class CodeBlockBackgroundMacOSTests: XCTestCase {
    func testMountedReadViewCodeBlockBackgroundExcludesOuterMarginsOnMacOS() throws {
        let document = NotesSemanticDocument(
            version: NotesSemanticDocument.currentVersion,
            blocks: [
                .paragraph([.init(text: "Before code", marks: [])]),
                .init(
                    type: .codeBlock,
                    content: [.init(
                        text: "# A simple reminder\nprint(\"Don't forget to review your notes.\")",
                        marks: []
                    )]
                ),
                .paragraph([.init(text: "After code", marks: [])])
            ]
        )
        let textView = try makeReadTextView(
            document: document,
            frame: NSRect(x: 0, y: 0, width: 640, height: 240)
        )
        let storage = try XCTUnwrap(textView.textStorage)
        let text = storage.string as NSString
        let firstLineRange = text.range(of: "# A simple reminder")
        let secondLineRange = text.range(of: "print(")
        XCTAssertNotEqual(firstLineRange.location, NSNotFound)
        XCTAssertNotEqual(secondLineRange.location, NSNotFound)

        let firstLineRect = try usedLineRect(in: textView, characterIndex: firstLineRange.location)
        let secondLineRect = try usedLineRect(in: textView, characterIndex: secondLineRange.location)
        let firstLineFragmentRect = try lineFragmentRect(
            in: textView,
            characterIndex: firstLineRange.location
        )
        let secondLineFragmentRect = try lineFragmentRect(
            in: textView,
            characterIndex: secondLineRange.location
        )
        let expectedBackgroundWidthRect = firstLineFragmentRect.union(secondLineFragmentRect)
        let backgroundRect = try XCTUnwrap(
            NoteTextCodeBlockBackgroundLayout.blockRects(
                in: storage,
                layoutManager: try XCTUnwrap(textView.layoutManager),
                textContainer: try XCTUnwrap(textView.textContainer),
                textContainerInset: textView.textContainerInset
            ).first
        )
        let padding = NoteTextAppearance.codeBlockVerticalPadding

        XCTAssertLessThanOrEqual(
            secondLineRect.minY - firstLineRect.maxY,
            2,
            "Expected code block line spacing to stay compact inside the block"
        )
        XCTAssertEqual(backgroundRect.minY, firstLineRect.minY - padding, accuracy: 2)
        XCTAssertEqual(backgroundRect.maxY, secondLineRect.maxY + padding, accuracy: 2)
        XCTAssertEqual(backgroundRect.minX, expectedBackgroundWidthRect.minX, accuracy: 2)
        XCTAssertEqual(backgroundRect.maxX, expectedBackgroundWidthRect.maxX, accuracy: 2)
    }

    private func usedLineRect(in textView: NSTextView, characterIndex: Int) throws -> CGRect {
        try lineRect(in: textView, characterIndex: characterIndex) { layoutManager, glyphIndex in
            layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
    }

    private func lineFragmentRect(in textView: NSTextView, characterIndex: Int) throws -> CGRect {
        try lineRect(in: textView, characterIndex: characterIndex) { layoutManager, glyphIndex in
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
    }

    private func lineRect(
        in textView: NSTextView,
        characterIndex: Int,
        resolve: (NSLayoutManager, Int) -> CGRect
    ) throws -> CGRect {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            throw XCTSkip("Missing text layout infrastructure")
        }

        textContainer.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        return resolve(layoutManager, glyphRange.location).offsetBy(
            dx: textView.textContainerInset.width,
            dy: textView.textContainerInset.height
        )
    }
}
#endif
