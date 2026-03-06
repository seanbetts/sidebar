@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct CanonicalInlineFormattingState {
        let bold: Bool
        let italic: Bool
        let underline: Bool
    }

    func normalizedEditorDocumentForRuntime(from source: AttributedString) -> AttributedString {
        var normalized = source
        canonicalizeEditorDocumentForRuntime(&normalized)
        return normalized
    }

    func canonicalizeEditorDocumentForRuntime(_ text: inout AttributedString) {
        NoteTextFormattingDefinition().constrainDocument(&text)
        canonicalizeInlineFormattingSemantics(in: &text)
        guard !text.characters.isEmpty else { return }

        for line in lineInfos(in: text) {
            let lineRange = attributedRange(for: line.range, in: text)
            let resolvedBlockKind: BlockKind = .paragraph
            text[lineRange].blockKind = resolvedBlockKind
            text[lineRange].listDepth = nil
            text[lineRange].codeLanguage = nil
            text[lineRange].inlineMarker = nil
            text[lineRange].listMarker = nil
            text[lineRange][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
            text[lineRange][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            applyInlineIntentStyling(in: &text, lineRange: lineRange, blockKind: resolvedBlockKind)
            let paragraphRange = lineRangeIncludingTrailingNewline(in: text, lineRange: lineRange)
            text[paragraphRange].paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(
                baseFontSize: baseFontSize
            )
        }
    }

    func canonicalInlineFormattingState(
        from run: AttributedString.Runs.Run
    ) -> CanonicalInlineFormattingState {
        let intents = run.inlinePresentationIntent ?? []
        let bold = intents.contains(.stronglyEmphasized)
            || swiftUIFontHasTrait(run.font, for: .stronglyEmphasized)
            || compatibilityFontHasTrait(run, intent: .stronglyEmphasized)
        let italic = intents.contains(.emphasized)
            || swiftUIFontHasTrait(run.font, for: .emphasized)
            || compatibilityFontHasTrait(run, intent: .emphasized)
        return CanonicalInlineFormattingState(
            bold: bold,
            italic: italic,
            underline: run.underlineStyle != nil
        )
    }

    private func canonicalizeInlineFormattingSemantics(in text: inout AttributedString) {
        for run in text.runs {
            let range = run.range
            let state = canonicalInlineFormattingState(from: run)
            var intents = text[range].inlinePresentationIntent ?? []

            if state.bold {
                intents.insert(.stronglyEmphasized)
            } else {
                intents.remove(.stronglyEmphasized)
            }

            if state.italic {
                intents.insert(.emphasized)
            } else {
                intents.remove(.emphasized)
            }

            text[range].inlinePresentationIntent = intents.isEmpty ? nil : intents
            text[range].underlineStyle = state.underline ? .single : nil
            text[range].strikethroughStyle = nil
        }
    }

    private func compatibilityFontHasTrait(
        _ run: AttributedString.Runs.Run,
        intent: InlinePresentationIntent
    ) -> Bool {
        guard let font = compatibilityPlatformFont(from: run) else { return false }
        switch intent {
        case .stronglyEmphasized:
            #if os(iOS)
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        case .emphasized:
            #if os(iOS)
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            #elseif os(macOS)
            return font.fontDescriptor.symbolicTraits.contains(.italic)
            #endif
        default:
            return false
        }
    }

    private func compatibilityPlatformFont(from run: AttributedString.Runs.Run) -> PlatformFont? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(sample)
        guard bridged.length > 0 else { return nil }
        return bridged.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
    }
}
