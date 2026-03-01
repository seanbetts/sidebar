import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeMarkdownCodeBlockTests: XCTestCase {
    func testApplyCodeBlockSetsLanguageWhenProvided() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadText("print(\"hello\")")
        let line = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        viewModel.applyCodeBlock(language: "swift")

        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .codeBlock)
        XCTAssertEqual(viewModel.attributedContent[updatedLine].codeLanguage, "swift")
        let intent = viewModel.attributedContent[updatedLine]
            .runs
            .first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        XCTAssertEqual(codeBlockLanguageHint(in: intent), "swift")
    }

    func testApplyCodeBlockClearsLanguageWhenNotProvided() async {
        let viewModel = NativeMarkdownEditorViewModel()
        viewModel.loadText("```swift\nprint(\"hello\")\n```")
        let line = firstLine(in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: line.lowerBound..<line.upperBound)

        viewModel.applyCodeBlock(language: nil)

        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent.blockKind(in: updatedLine), .codeBlock)
        XCTAssertNil(viewModel.attributedContent[updatedLine].codeLanguage)
        let intent = viewModel.attributedContent[updatedLine]
            .runs
            .first?[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
        XCTAssertNil(codeBlockLanguageHint(in: intent))
    }

    private func firstLine(in text: AttributedString) -> Range<AttributedString.Index> {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                return text.startIndex..<cursor
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return text.startIndex..<text.endIndex
    }

    private func codeBlockLanguageHint(in intent: PresentationIntent?) -> String? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .codeBlock(let languageHint) = component.kind {
                return languageHint
            }
        }
        return nil
    }
}
