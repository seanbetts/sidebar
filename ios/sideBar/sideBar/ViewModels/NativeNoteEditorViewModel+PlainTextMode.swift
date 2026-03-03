@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    public func setPlainTextRuntimeModeEnabled(_ enabled: Bool) {
        guard plainTextRuntimeModeEnabled != enabled else { return }
        plainTextRuntimeModeEnabled = enabled
        guard enabled else { return }
        normalizeCurrentContentForPlainTextRuntime()
    }

    func plainTextRuntimeNormalizedContent(from content: AttributedString) -> AttributedString {
        let plainText = String(content.characters)
        var normalized = AttributedString(plainText)
        guard !normalized.characters.isEmpty else { return normalized }

        let fullRange = normalized.startIndex..<normalized.endIndex
        normalized[fullRange].blockKind = .paragraph
        normalized[fullRange].listDepth = nil
        normalized[fullRange].codeLanguage = nil
        normalized[fullRange].inlinePresentationIntent = []
        normalized[fullRange].strikethroughStyle = nil
        normalized[fullRange].underlineStyle = nil
        normalized[fullRange].link = nil
        normalized[fullRange][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1
        )
        normalized[fullRange][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
        setFont(bodyFont, platformFont: platformBaseFont(for: .paragraph), in: &normalized, range: fullRange)
        setForegroundColor(baseForegroundColor(for: .paragraph), in: &normalized, range: fullRange)
        setBackgroundColor(nil, in: &normalized, range: fullRange)
        if let style = plainTextRuntimeParagraphStyle() {
            normalized[fullRange].paragraphStyle = style
        }
        _ = applyDetectedLinks(in: &normalized)
        return normalized
    }

    func plainTextRuntimeParagraphStyle() -> NSParagraphStyle? {
        guard let baseStyle = paragraphStyle(for: .paragraph, listDepth: nil) else {
            return nil
        }
        guard let mutable = baseStyle.mutableCopy() as? NSMutableParagraphStyle else {
            return baseStyle
        }
        mutable.paragraphSpacingBefore = 0
        mutable.paragraphSpacing = 0
        return mutable
    }

    func normalizeCurrentContentForPlainTextRuntime() {
        let snapshot = selectionSnapshot(in: attributedContent)
        let normalized = plainTextRuntimeNormalizedContent(from: attributedContent)
        guard normalized != attributedContent else { return }
        attributedContent = normalized
        selection = selection(from: snapshot, in: normalized)
    }
}
