@preconcurrency import Foundation
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private struct PreservedInlineRun {
        let lowerOffset: Int
        let upperOffset: Int
        let inlineIntents: InlinePresentationIntent
        let underlineStyle: Text.LineStyle?
    }

    func setEnabledFormattingCapabilities(_ capabilities: Set<NoteFormattingCapability>) {
        guard enabledFormattingCapabilities != capabilities else { return }
        enabledFormattingCapabilities = capabilities
        guard plainTextRuntimeModeEnabled else { return }
        normalizeCurrentContentForPlainTextRuntime()
    }

    public func setPlainTextRuntimeModeEnabled(_ enabled: Bool) {
        guard plainTextRuntimeModeEnabled != enabled else { return }
        plainTextRuntimeModeEnabled = enabled
        guard enabled else { return }
        prefixRefreshTask?.cancel()
        prefixRefreshTask = nil
        pendingPrefixRefreshScope = nil
        usesInjectedListMarkers = false
        normalizeCurrentContentForPlainTextRuntime()
    }

    func plainTextRuntimeNormalizedContent(from content: AttributedString) -> AttributedString {
        let preservedInlineRuns = plainTextRuntimePreservedInlineRuns(from: content)
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
        applyPlainTextRuntimePreservedInlineRuns(preservedInlineRuns, to: &normalized)
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
        // Keep blank lines visually identical to content lines in plain-text mode.
        mutable.lineSpacing = 0
        mutable.lineHeightMultiple = 0
        mutable.minimumLineHeight = 0
        mutable.maximumLineHeight = 0
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

    private func plainTextRuntimePreservedInlineRuns(
        from content: AttributedString
    ) -> [PreservedInlineRun] {
        guard !content.characters.isEmpty else { return [] }
        guard !enabledFormattingCapabilities.isEmpty else { return [] }

        var preservedRuns: [PreservedInlineRun] = []
        for run in content.runs {
            var preservedIntents = preservedInlineIntents(from: run.inlinePresentationIntent ?? [])
            if enabledFormattingCapabilities.contains(.bold),
               runHasBoldTraitForPlainTextRuntime(run) {
                preservedIntents.insert(.stronglyEmphasized)
            }
            let underlineStyle = enabledFormattingCapabilities.contains(.underline)
                ? run.underlineStyle
                : nil
            guard preservedIntents != [] || underlineStyle != nil else { continue }

            let lowerOffset = content.characters.distance(
                from: content.startIndex,
                to: run.range.lowerBound
            )
            let upperOffset = content.characters.distance(
                from: content.startIndex,
                to: run.range.upperBound
            )
            guard lowerOffset < upperOffset else { continue }
            preservedRuns.append(
                PreservedInlineRun(
                    lowerOffset: lowerOffset,
                    upperOffset: upperOffset,
                    inlineIntents: preservedIntents,
                    underlineStyle: underlineStyle
                )
            )
        }
        return preservedRuns
    }

    private func runHasBoldTraitForPlainTextRuntime(_ run: AttributedString.Runs.Run) -> Bool {
        #if os(iOS)
        guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #elseif os(macOS)
        if let font = run[AttributeScopes.AppKitAttributes.FontAttribute.self] {
            return font.fontDescriptor.symbolicTraits.contains(.bold)
        }
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        let bridged = NSAttributedString(sample)
        guard let font = bridged.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            return false
        }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
        #endif
    }

    private func preservedInlineIntents(
        from intents: InlinePresentationIntent
    ) -> InlinePresentationIntent {
        var preserved: InlinePresentationIntent = []
        if enabledFormattingCapabilities.contains(.bold),
           intents.contains(.stronglyEmphasized) {
            preserved.insert(.stronglyEmphasized)
        }
        if enabledFormattingCapabilities.contains(.italic),
           intents.contains(.emphasized) {
            preserved.insert(.emphasized)
        }
        return preserved
    }

    private func applyPlainTextRuntimePreservedInlineRuns(
        _ runs: [PreservedInlineRun],
        to normalized: inout AttributedString
    ) {
        guard !runs.isEmpty else { return }
        let characterCount = normalized.characters.count
        for run in runs {
            guard run.upperOffset <= characterCount else { continue }
            let lower = normalized.index(
                normalized.startIndex,
                offsetByCharacters: run.lowerOffset
            )
            let upper = normalized.index(
                normalized.startIndex,
                offsetByCharacters: run.upperOffset
            )
            let range = lower..<upper

            if run.inlineIntents != [] {
                normalized[range].inlinePresentationIntent = run.inlineIntents
                let bold = run.inlineIntents.contains(.stronglyEmphasized)
                let italic = run.inlineIntents.contains(.emphasized)
                var styledFont = bodyFont
                if bold {
                    styledFont = styledFont.weight(.bold)
                }
                if italic {
                    styledFont = styledFont.italic()
                }
                if bold || italic {
                    let platformStyled = platformFontApplyingTraits(
                        platformBaseFont(for: .paragraph),
                        bold: bold,
                        italic: italic
                    )
                    setFont(styledFont, platformFont: platformStyled, in: &normalized, range: range)
                }
            }

            if let underlineStyle = run.underlineStyle {
                normalized[range].underlineStyle = underlineStyle
            }
        }
    }
}
