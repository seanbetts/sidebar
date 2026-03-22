import SwiftUI
import XCTest
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeEditorFormattingTests: XCTestCase {
    func testSelectedRangeFormattingStateUpdatesIndividuallyPerControl() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Title\nhello")

        func bodyRange() -> Range<AttributedString.Index> {
            let lowerBound = viewModel.attributedContent.index(
                viewModel.attributedContent.startIndex,
                offsetByCharacters: 6
            )
            return lowerBound..<viewModel.attributedContent.endIndex
        }

        viewModel.selection = AttributedTextSelection(range: bodyRange())

        XCTAssertFalse(viewModel.isFormattingActive(.bold))
        viewModel.applyFormatting(.bold)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertFalse(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(range: bodyRange())
        viewModel.applyFormatting(.italic)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.selection = AttributedTextSelection(range: bodyRange())
        viewModel.applyFormatting(.underline)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertTrue(viewModel.isFormattingActive(.underline))
    }

    func testInsertionPointFormattingStateUpdatesIndividuallyPerControlAndTypedText() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("Title\nHi")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        XCTAssertFalse(viewModel.isFormattingActive(.bold))
        viewModel.applyFormatting(.bold)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertFalse(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.applyFormatting(.italic)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertFalse(viewModel.isFormattingActive(.underline))

        viewModel.applyFormatting(.underline)
        XCTAssertTrue(viewModel.isFormattingActive(.bold))
        XCTAssertTrue(viewModel.isFormattingActive(.italic))
        XCTAssertTrue(viewModel.isFormattingActive(.underline))

        noteAppendTypedText("!", to: viewModel)

        let punctuationStart = viewModel.attributedContent.index(
            viewModel.attributedContent.startIndex,
            offsetByCharacters: 8
        )
        let punctuationEnd = viewModel.attributedContent.index(afterCharacter: punctuationStart)

        XCTAssertTrue(
            noteRangeHasBoldTrait(
                viewModel.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
        XCTAssertTrue(
            noteRangeHasItalicTrait(
                viewModel.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
        XCTAssertTrue(
            noteRangeIsUnderlined(
                viewModel.attributedContent,
                range: punctuationStart..<punctuationEnd
            )
        )
    }
}
