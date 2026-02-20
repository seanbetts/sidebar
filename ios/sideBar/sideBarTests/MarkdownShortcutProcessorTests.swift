import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class MarkdownShortcutProcessorTests: XCTestCase {
    func testProcessShortcutsConvertsHorizontalRuleShortcut() {
        var text = AttributedString("---\n")
        let selection = AttributedTextSelection(range: text.endIndex..<text.endIndex)

        let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &text,
            selection: selection,
            lastInsertedCharacter: "\n"
        )

        XCTAssertNotNil(newSelection)
        let range = firstLineRange(in: text)
        XCTAssertEqual(text.blockKind(in: range), .horizontalRule)
    }

    func testProcessShortcutsConvertsCodeFenceShortcutWithLanguage() {
        var text = AttributedString("```swift\n")
        let selection = AttributedTextSelection(range: text.endIndex..<text.endIndex)

        let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &text,
            selection: selection,
            lastInsertedCharacter: "\n"
        )

        XCTAssertNotNil(newSelection)
        let range = firstLineRange(in: text)
        XCTAssertEqual(text.blockKind(in: range), .codeBlock)
        XCTAssertEqual(firstCodeLanguage(in: text, range: range), "swift")
    }

    func testProcessShortcutsTreatsTaskPrefixAsTaskBeforeBullet() {
        var text = AttributedString("- [x] done\n")
        let selection = AttributedTextSelection(range: text.endIndex..<text.endIndex)

        let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &text,
            selection: selection,
            lastInsertedCharacter: "\n"
        )

        XCTAssertNotNil(newSelection)
        let range = firstLineRange(in: text)
        XCTAssertEqual(text.blockKind(in: range), .taskChecked)
    }

    func testProcessShortcutsSupportsPlusTaskPrefix() {
        var text = AttributedString("+ [ ] todo\n")
        let selection = AttributedTextSelection(range: text.endIndex..<text.endIndex)

        let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &text,
            selection: selection,
            lastInsertedCharacter: "\n"
        )

        XCTAssertNotNil(newSelection)
        let range = firstLineRange(in: text)
        XCTAssertEqual(text.blockKind(in: range), .taskUnchecked)
    }

    private func firstLineRange(in text: AttributedString) -> Range<AttributedString.Index> {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                return text.startIndex..<cursor
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return text.startIndex..<text.endIndex
    }

    private func firstCodeLanguage(
        in text: AttributedString,
        range: Range<AttributedString.Index>
    ) -> String? {
        for run in text[range].runs {
            if let language = run.codeLanguage {
                return language
            }
        }
        return nil
    }
}
