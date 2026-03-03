import XCTest
import SwiftUI
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorPersistenceTests: XCTestCase {
    func testCurrentPersistenceSnapshotExportsPlainTextAndCanonicalRTF() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let snapshot = viewModel.currentPersistenceSnapshot()
        XCTAssertEqual(snapshot.plainText, "hello")
        XCTAssertFalse(snapshot.canonicalContent.isEmpty)
        XCTAssertEqual(
            NotesRichTextCodec.decodeBase64RTFToPlainText(snapshot.canonicalContent),
            "hello"
        )
    }

    func testPersistenceSnapshotRoundTripPreservesBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")

        let fullRange = characterRange(length: 5, in: viewModel.attributedContent)
        viewModel.selection = AttributedTextSelection(range: fullRange)
        viewModel.applyFormatting(.bold)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        let hasBoldFont = reloaded.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        }
        XCTAssertTrue(hasBoldFont)
    }

    func testPersistenceSnapshotRoundTripPreservesBulletListFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("item")

        let first = viewModel.attributedContent.startIndex
        let next = viewModel.attributedContent.index(afterCharacter: first)
        viewModel.selection = AttributedTextSelection(range: first..<next)
        viewModel.applyFormatting(.bulletList)

        let snapshot = viewModel.currentPersistenceSnapshot()
        let reloaded = NativeNoteEditorViewModel()
        reloaded.loadDocument(canonicalContent: snapshot.canonicalContent, plainText: snapshot.plainText)

        XCTAssertTrue(snapshot.plainText.hasPrefix("• "))
        XCTAssertTrue(reloaded.currentPlainText().hasPrefix("• "))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func characterRange(
    length: Int,
    in text: AttributedString
) -> Range<AttributedString.Index> {
    var index = text.startIndex
    for _ in 0..<length {
        index = text.index(afterCharacter: index)
    }
    return text.startIndex..<index
}
