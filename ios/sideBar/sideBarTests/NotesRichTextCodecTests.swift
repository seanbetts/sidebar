import Foundation
import SwiftUI
import XCTest
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
final class NotesRichTextCodecTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let text = "Hello\nWorld"
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF(text)
        let decoded = NotesRichTextCodec.decodeBase64RTFToPlainText(encoded)

        XCTAssertEqual(decoded, text)
    }

    func testNormalizeWriteInputUsesExplicitPlainText() {
        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: "ignored",
            plainText: "Body"
        )

        XCTAssertEqual(normalized.plainText, "Body")
        XCTAssertNotNil(NotesRichTextCodec.decodeBase64RTFToPlainText(normalized.content))
    }

    func testNormalizeWriteInputPreservesCanonicalContentWhenPlainTextProvided() {
        let canonical = NotesRichTextCodec.encodePlainTextToBase64RTF("Body")

        let normalized = NotesRichTextCodec.normalizeWriteInput(
            content: canonical,
            plainText: "Body"
        )

        XCTAssertEqual(normalized.content, canonical)
        XCTAssertEqual(normalized.plainText, "Body")
    }

    func testNormalizeWriteInputDecodesCanonicalContent() {
        let canonical = NotesRichTextCodec.encodePlainTextToBase64RTF("Stored body")

        let normalized = NotesRichTextCodec.normalizeWriteInput(content: canonical)

        XCTAssertEqual(normalized.content, canonical)
        XCTAssertEqual(normalized.plainText, "Stored body")
    }

    func testNormalizeWriteInputDerivesPlainTextFromEncodedSnapshot() {
        let normalized = NotesRichTextCodec.normalizeWriteInput(content: "Derived body")
        let decoded = NotesRichTextCodec.decodeBase64RTFToPlainText(normalized.content)

        XCTAssertEqual(normalized.plainText, decoded)
    }

    func testNotePayloadDecodesPlainTextFromResponse() throws {
        let encoded = NotesRichTextCodec.encodePlainTextToBase64RTF("Decoded body")
        let json = """
        {
          "id": "n1",
          "name": "Title.md",
          "content": "\(encoded)",
          "plain_text": "Decoded body",
          "content_format": "rtf",
          "path": "n1",
          "modified": 1,
          "created": 1
        }
        """

        let payload = try JSONDecoder().decode(
            NotePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.content, encoded)
        XCTAssertEqual(payload.plainText, "Decoded body")
    }

    func testNotePayloadDropsRawFallbackWhenCanonicalDecodeFails() throws {
        let json = """
        {
          "id": "n2",
          "name": "Title.md",
          "content": "not-base64",
          "path": "n2",
          "modified": 1,
          "created": 1
        }
        """

        let payload = try JSONDecoder().decode(
            NotePayload.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(payload.content, "not-base64")
        XCTAssertEqual(payload.plainText, "")
    }

    func testDecodeBase64RTFToAttributedStringPreservesBoldFontTraits() throws {
        let encoded = try makeEncodedRTF(
            string: "Bold",
            attributes: platformAttributes(
                font: boldSystemFont(size: 16),
                underline: nil
            )
        )

        let decoded = try XCTUnwrap(NotesRichTextCodec.decodeBase64RTFToAttributedString(encoded))
        XCTAssertTrue(decoded.runs.contains { run in
            hasBoldTrait(run)
        })
    }

    func testDecodeBase64RTFToAttributedStringPreservesItalicFontTraits() throws {
        let encoded = try makeEncodedRTF(
            string: "Styled",
            attributes: platformAttributes(
                font: italicSystemFont(size: 16),
                underline: NSUnderlineStyle.single.rawValue
            )
        )

        let decoded = try XCTUnwrap(NotesRichTextCodec.decodeBase64RTFToAttributedString(encoded))
        XCTAssertTrue(decoded.runs.contains { run in
            hasItalicTrait(run)
        })
    }

    func testEncodeAttributedStringToBase64RTFPreservesUnderlineFormatting() throws {
        var text = AttributedString("Underlined")
        text[text.startIndex..<text.endIndex].underlineStyle = .single

        let encoded = try XCTUnwrap(NotesRichTextCodec.encodeAttributedStringToBase64RTF(text))
        let decoded = try XCTUnwrap(NotesRichTextCodec.decodeBase64RTFToAttributedString(encoded))
        let decodedRange = decoded.startIndex..<decoded.endIndex

        XCTAssertEqual(decoded[decodedRange].underlineStyle, .single)
    }
}

private func hasBoldTrait(_ run: AttributedString.Runs.Run) -> Bool {
    #if os(iOS)
    guard let font = bridgedPlatformFont(from: run) as? UIFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.traitBold)
    #elseif os(macOS)
    guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.bold)
    #endif
}

private func hasItalicTrait(_ run: AttributedString.Runs.Run) -> Bool {
    #if os(iOS)
    guard let font = bridgedPlatformFont(from: run) as? UIFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
    #elseif os(macOS)
    guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.italic)
    #endif
}

private func bridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
    var sample = AttributedString("x")
    let range = sample.startIndex..<sample.endIndex
    sample[range].mergeAttributes(run.attributes)
    let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
        ?? NSAttributedString(sample)
    return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
}

private func makeEncodedRTF(string: String, attributes: [NSAttributedString.Key: Any]) throws -> String {
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let data = try attributed.data(
        from: NSRange(location: 0, length: attributed.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    return data.base64EncodedString()
}

private func platformAttributes(
    font: AnyObject,
    underline: Int?
) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [.font: font]
    if let underline {
        attributes[.underlineStyle] = underline
    }
    return attributes
}

#if os(iOS)
private func boldSystemFont(size: CGFloat) -> UIFont {
    UIFont.boldSystemFont(ofSize: size)
}

private func italicSystemFont(size: CGFloat) -> UIFont {
    UIFont.italicSystemFont(ofSize: size)
}
#elseif os(macOS)
private func boldSystemFont(size: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: .bold)
}

private func italicSystemFont(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size)
    return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
}
#endif
