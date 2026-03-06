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
        syncUnderlineStyles(from: attributed, into: &normalized)
        return normalized
    }

    /// Encode attributed text to canonical Base64 RTF bytes.
    static func encodeAttributedStringToBase64RTF(
        _ content: AttributedString,
        baseFontSize: CGFloat? = nil
    ) -> String? {
        let attributed = bridgedAttributedStringForRTFExport(
            from: content,
            baseFontSize: baseFontSize
        )
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

    private static func bridgedAttributedStringForRTFExport(
        from content: AttributedString,
        baseFontSize: CGFloat?
    ) -> NSAttributedString {
        let base = (try? NSAttributedString(content, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(content)
        guard base.length > 0 else { return base }

        let mutable = NSMutableAttributedString(attributedString: base)
        let plainText = String(content.characters)

        for run in content.runs {
            let nsRange = nsRange(for: run.range, in: content, plainText: plainText)
            guard nsRange.length > 0 else { continue }

            let pointSize = baseFontSize
                ?? (mutable.attribute(.font, at: nsRange.location, effectiveRange: nil) as? NotePlatformFont)?
                .pointSize
                ?? noteBridgedPlatformFont(from: run.attributes)?.pointSize
                ?? 16
            let traits = noteInlineTraits(for: run)
            let font = notePlatformFont(
                baseFontSize: pointSize,
                bold: traits.bold,
                italic: traits.italic
            )
            mutable.addAttribute(.font, value: font, range: nsRange)

            guard run.underlineStyle != nil else { continue }
            mutable.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: nsRange
            )
        }

        return mutable
    }

    private static func nsRange(
        for range: Range<AttributedString.Index>,
        in content: AttributedString,
        plainText: String
    ) -> NSRange {
        let lowerCharacterOffset = content.characters.distance(
            from: content.startIndex,
            to: range.lowerBound
        )
        let upperCharacterOffset = content.characters.distance(
            from: content.startIndex,
            to: range.upperBound
        )
        let lower = plainText.index(plainText.startIndex, offsetBy: lowerCharacterOffset)
        let upper = plainText.index(plainText.startIndex, offsetBy: upperCharacterOffset)
        return NSRange(
            location: lower.utf16Offset(in: plainText),
            length: upper.utf16Offset(in: plainText) - lower.utf16Offset(in: plainText)
        )
    }

    private static func syncUnderlineStyles(
        from source: NSAttributedString,
        into text: inout AttributedString
    ) {
        let plainText = source.string
        guard !plainText.isEmpty else { return }

        source.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard let rawValue = value as? Int, rawValue != 0 else { return }
            guard let stringRange = Range(range, in: plainText) else { return }
            let lowerOffset = plainText.distance(from: plainText.startIndex, to: stringRange.lowerBound)
            let upperOffset = plainText.distance(from: plainText.startIndex, to: stringRange.upperBound)
            let lower = text.index(text.startIndex, offsetByCharacters: lowerOffset)
            let upper = text.index(text.startIndex, offsetByCharacters: upperOffset)
            text[lower..<upper].underlineStyle = .single
        }
    }

    private static func noteInlineTraits(
        for run: AttributedString.Runs.Run
    ) -> NoteInlineFormattingTraits {
        let swiftUIFontTraits = noteSwiftUIFontTraits(from: run.font)
        #if os(iOS)
        let platformFont = run[AttributeScopes.UIKitAttributes.FontAttribute.self]
        #else
        let platformFont: NotePlatformFont? = nil
        #endif
        let platformTraits = platformFont.map(notePlatformFontTraits(from:)) ??
            noteBridgedPlatformFont(from: run.attributes).map(notePlatformFontTraits(from:)) ??
            .plain
        return NoteInlineFormattingTraits(
            bold: swiftUIFontTraits.bold || platformTraits.bold,
            italic: swiftUIFontTraits.italic || platformTraits.italic
        )
    }
}
