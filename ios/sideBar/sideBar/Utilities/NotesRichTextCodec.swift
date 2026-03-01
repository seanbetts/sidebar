import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Helpers for Notes canonical rich-text transport.
enum NotesRichTextCodec {
    /// Encode plain text as Base64 RTF bytes.
    static func encodePlainTextToBase64RTF(_ plainText: String) -> String {
        let attributed = NSMutableAttributedString(string: plainText)
        #if os(iOS)
        let font = UIFont.systemFont(ofSize: 16)
        #elseif os(macOS)
        let font = NSFont.systemFont(ofSize: 16)
        #endif
        if attributed.length > 0 {
            attributed.addAttribute(
                .font,
                value: font,
                range: NSRange(location: 0, length: attributed.length)
            )
        }
        let rtfData: Data
        do {
            rtfData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            return fallbackRTFData(from: plainText).base64EncodedString()
        }
        return rtfData.base64EncodedString()
    }

    /// Decode Base64 RTF bytes to plain text.
    static func decodeBase64RTFToPlainText(_ content: String) -> String? {
        guard let decoded = Data(base64Encoded: content) else {
            return nil
        }
        guard let attributed = try? NSAttributedString(
            data: decoded,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else {
            return nil
        }
        return attributed.string
    }

    /// Normalize mixed legacy/canonical input to canonical write payload.
    static func normalizeWriteInput(
        content: String,
        plainText: String? = nil
    ) -> (content: String, plainText: String) {
        if let plainText {
            return (
                content: encodePlainTextToBase64RTF(plainText),
                plainText: plainText
            )
        }
        if let decoded = decodeBase64RTFToPlainText(content) {
            return (content: content, plainText: decoded)
        }
        return (
            content: encodePlainTextToBase64RTF(content),
            plainText: content
        )
    }

    private static func fallbackRTFData(from plainText: String) -> Data {
        let normalized = plainText.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let escaped = normalized
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\n", with: "\\par\n")
        return Data("{\\rtf1\\ansi\n\(escaped)\n}".utf8)
    }
}
