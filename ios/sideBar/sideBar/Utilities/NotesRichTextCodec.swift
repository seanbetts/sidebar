import Foundation
import SwiftUI
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

    /// Decode canonical Base64 RTF bytes to attributed text.
    static func decodeBase64RTFToAttributedString(_ content: String) -> AttributedString? {
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
        var normalized = AttributedString(attributed)
        normalizeDecodedEditorText(&normalized)
        return normalized
    }

    /// Encode attributed text to canonical Base64 RTF bytes.
    static func encodeAttributedStringToBase64RTF(_ content: AttributedString) -> String? {
        let attributed = NSAttributedString(content)
        let range = NSRange(location: 0, length: attributed.length)
        guard let rtfData = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            return nil
        }
        return rtfData.base64EncodedString()
    }

    /// Normalize mixed legacy/canonical input to canonical write payload.
    static func normalizeWriteInput(
        content: String,
        plainText: String? = nil
    ) -> (content: String, plainText: String) {
        if let plainText {
            if decodeBase64RTFToPlainText(content) != nil {
                return (content: content, plainText: plainText)
            }
            let encoded = encodePlainTextToBase64RTF(plainText)
            let resolvedPlainText =
                decodeBase64RTFToPlainText(encoded) ?? plainText
            return (
                content: encoded,
                plainText: resolvedPlainText
            )
        }
        if let decoded = decodeBase64RTFToPlainText(content) {
            return (content: content, plainText: decoded)
        }
        let encoded = encodePlainTextToBase64RTF(content)
        let resolvedPlainText = decodeBase64RTFToPlainText(encoded) ?? content
        return (
            content: encoded,
            plainText: resolvedPlainText
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

    private static func normalizeDecodedEditorText(_ text: inout AttributedString) {
        for run in text.runs {
            let range = run.range
            let traits = inlineTraits(from: run)

            var intents = text[range].inlinePresentationIntent ?? []
            if traits.bold {
                intents.insert(.stronglyEmphasized)
            } else {
                intents.remove(.stronglyEmphasized)
            }
            if traits.italic {
                intents.insert(.emphasized)
            } else {
                intents.remove(.emphasized)
            }
            text[range].inlinePresentationIntent = intents.isEmpty ? nil : intents

            if text[range].underlineStyle != nil {
                text[range].underlineStyle = .single
            }
            text[range].strikethroughStyle = nil
            text[range].font = nil
#if os(iOS)
            text[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = nil
#endif
        }
    }

    private static func inlineTraits(from run: AttributedString.Runs.Run) -> (bold: Bool, italic: Bool) {
#if os(iOS)
        if let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] {
            let traits = font.fontDescriptor.symbolicTraits
            return (
                bold: traits.contains(.traitBold),
                italic: traits.contains(.traitItalic)
            )
        }
#elseif os(macOS)
        if let font = bridgedPlatformFont(from: run) as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            return (
                bold: traits.contains(.bold),
                italic: traits.contains(.italic)
            )
        }
#endif
        return (false, false)
    }

#if os(macOS)
    private static func bridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        let bridged = NSAttributedString(sample)
        return bridged.attribute(.font, at: 0, effectiveRange: nil) as AnyObject?
    }
#endif
}
