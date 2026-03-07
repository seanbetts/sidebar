import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class AttributedNoteFormattingDefinitionTests: XCTestCase {
    func testConstrainDocumentRemovesUnsupportedFoundationPresentationAttributes() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: PresentationIntent(.unorderedList, identity: 2)
        )
        content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = "•"
        content[range].strikethroughStyle = .single
        content[range].underlineStyle = .single

        NoteTextFormattingDefinition(baseFontSize: 18).constrainDocument(&content)

        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self])
        XCTAssertNil(content[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self])
        XCTAssertNil(content[range].strikethroughStyle)
        XCTAssertEqual(content[range].underlineStyle, .single)
    }

    func testConstrainDocumentNormalizesSupportedInlineFonts() throws {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
        content[range].font = .system(size: 14, weight: .bold).italic()

        NoteTextFormattingDefinition(baseFontSize: 24).constrainDocument(&content)

        let resolved = content[range].font?.resolve(in: EnvironmentValues().fontResolutionContext)
        XCTAssertEqual(resolved?.isBold, true)
        XCTAssertEqual(resolved?.isItalic, true)
        let exported = try XCTUnwrap(
            NotesRichTextCodec.encodeAttributedStringToBase64RTF(
                content,
                baseFontSize: 24
            )
        )
        XCTAssertEqual(legacyRTFFirstRunPointSize(in: exported) ?? 0, 24, accuracy: 1.0)
    }

    func testConstrainDocumentDoesNotPromoteBridgedPlatformFontTraitsWithoutSwiftUIFont() {
        var content = AttributedString("hello")
        let range = content.startIndex..<content.endIndex
#if os(iOS)
        content[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = UIFont.boldSystemFont(ofSize: 14)
#elseif os(macOS)
        content[range][AttributeScopes.AppKitAttributes.FontAttribute.self] = NSFont.systemFont(
            ofSize: 14,
            weight: .bold
        )
#endif
        content[range].font = nil

        NoteTextFormattingDefinition(baseFontSize: 20).constrainDocument(&content)

        XCTAssertFalse(noteRangeHasBoldTrait(content, range: range))
    }
}

private func legacyRTFFirstRunPointSize(in content: String) -> CGFloat? {
    guard let data = Data(base64Encoded: content),
          let attributed = try? NSAttributedString(
              data: data,
              options: [.documentType: NSAttributedString.DocumentType.rtf],
              documentAttributes: nil
          ),
          attributed.length > 0 else {
        return nil
    }
    #if os(iOS)
    return (attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize
    #elseif os(macOS)
    return (attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
    #endif
}
