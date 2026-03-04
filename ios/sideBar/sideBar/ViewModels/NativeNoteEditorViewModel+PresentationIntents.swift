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
    func hasInlineIntent(_ intent: InlinePresentationIntent) -> Bool {
        let nonEmptyRanges = selectionRanges().ranges.filter { !$0.isEmpty }
        if !nonEmptyRanges.isEmpty {
            return nonEmptyRanges.allSatisfy { range in
                let runs = attributedContent[range].runs.filter { run in
                    run.inlineMarker != true && run.listMarker != true
                }
                guard !runs.isEmpty else { return false }
                return runs.allSatisfy { run in
                    runHasInlineIntentOrTrait(run, intent: intent)
                }
            }
        }

        let attrs = selection.typingAttributes(in: attributedContent)
        if typingAttributesHaveInlineIntentOrTrait(attrs, intent: intent) {
            return true
        }

        switch selection.indices(in: attributedContent) {
        case .insertionPoint(let index):
            guard index > attributedContent.startIndex else { return false }
            let previous = attributedContent.index(beforeCharacter: index)
            let previousRange = previous..<index
            return rangeHasInlineIntentOrTrait(previousRange, intent: intent)
        case .ranges(let ranges):
            for range in ranges.ranges where range.isEmpty {
                guard range.lowerBound > attributedContent.startIndex else { return false }
                let previous = attributedContent.index(beforeCharacter: range.lowerBound)
                let previousRange = previous..<range.lowerBound
                return rangeHasInlineIntentOrTrait(previousRange, intent: intent)
            }
            return false
        }
    }

    func applyInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>? = nil
    ) {
        if let range {
            applyInlineIntentToRange(intent, enabled: enabled, range: range)
            return
        }
        transformSelectionAttributes { attrs in
            updateInlineIntent(intent, enabled: enabled, attrs: &attrs)
        }
    }

    func updateInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        attrs: inout AttributeContainer
    ) {
        var intents = attrs.inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attrs.inlinePresentationIntent = intents

        if intent == .code {
            let blockKind = attrs.blockKind
            if enabled {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attrs)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &attrs)
                setBackgroundColor(Self.noteStyle.codeBackground, in: &attrs)
            } else {
                setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
                setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
                setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
            }
            return
        }

        let blockKind = attrs.blockKind
        let isBold = intents.contains(.stronglyEmphasized)
        let isItalic = intents.contains(.emphasized)
        let styledFont = inlineStyledFont(
            blockKind: blockKind,
            bold: isBold,
            italic: isItalic
        )
        let platformStyled = platformFontApplyingTraits(
            platformBaseFont(for: blockKind),
            bold: isBold,
            italic: isItalic
        )
        setFont(styledFont, platformFont: platformStyled, in: &attrs)
    }

    func applyInlineIntentToRange(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>
    ) {
        var intents = attributedContent[range].inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attributedContent[range].inlinePresentationIntent = intents

        if intent == .code {
            if enabled {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attributedContent, range: range)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &attributedContent, range: range)
                setBackgroundColor(Self.noteStyle.codeBackground, in: &attributedContent, range: range)
            } else {
                let blockKind = attributedContent.blockKind(in: range)
                setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attributedContent, range: range)
                setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
                setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
            }
            return
        }

        let blockKind = attributedContent.blockKind(in: range)
        let isBold = intents.contains(.stronglyEmphasized)
        let isItalic = intents.contains(.emphasized)
        let styledFont = inlineStyledFont(
            blockKind: blockKind,
            bold: isBold,
            italic: isItalic
        )
        let platformStyled = platformFontApplyingTraits(
            platformBaseFont(for: blockKind),
            bold: isBold,
            italic: isItalic
        )
        setFont(styledFont, platformFont: platformStyled, in: &attributedContent, range: range)
    }

    func applyBlockStyle(blockKind: BlockKind, range: Range<AttributedString.Index>) {
        let font = blockKind == .codeBlock ? blockCodeFont : baseFont(for: blockKind)
        let platformFont = blockKind == .codeBlock ? platformInlineCodeFont() : platformBaseFont(for: blockKind)
        setFont(font, platformFont: platformFont, in: &attributedContent, range: range)
        setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        let listDepth = attributedContent[range].listDepth
        if let paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth) {
            attributedContent[range].paragraphStyle = paragraphStyle
        }
        if blockKind == .taskChecked {
            setStrikethrough(true, in: &attributedContent, range: range)
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &attributedContent, range: range)
        } else if blockKind == .taskUnchecked {
            setStrikethrough(false, in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    func applyPresentationIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) {
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(level: headingLevel, range: range)
            return
        }
        if applyListIntent(blockKind: blockKind, listDepth: listDepth, range: range) {
            return
        }
        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            let languageHint = attributedContent[range].codeLanguage
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: languageHint),
                identity: 1
            )
        case .horizontalRule:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1
            )
        @unknown default:
            return
        }
    }

    func headingLevel(for blockKind: BlockKind) -> Int? {
        switch blockKind {
        case .heading1: return 1
        case .heading2: return 2
        case .heading3: return 3
        case .heading4: return 4
        case .heading5: return 5
        case .heading6: return 6
        default: return nil
        }
    }

    func applyHeadingIntent(level: Int, range: Range<AttributedString.Index>) {
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    func applyListIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) -> Bool {
        guard blockKind == .bulletList
            || blockKind == .orderedList
            || blockKind == .taskChecked
            || blockKind == .taskUnchecked
        else { return false }
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
        let listId = listDepth ?? 1
        let listIntent = PresentationIntent(listKind, identity: listId)
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: 1),
            identity: listId * 1000 + 1,
            parent: listIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        return true
    }

    func listDelimiter(for blockKind: BlockKind) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskChecked:
            return "☑"
        case .taskUnchecked:
            return "☐"
        default:
            return nil
        }
    }

    func rangeHasInlineIntentOrTrait(
        _ range: Range<AttributedString.Index>,
        intent: InlinePresentationIntent
    ) -> Bool {
        let runs = attributedContent[range].runs.filter { run in
            run.inlineMarker != true && run.listMarker != true
        }
        guard !runs.isEmpty else { return false }
        return runs.allSatisfy { run in
            runHasInlineIntentOrTrait(run, intent: intent)
        }
    }

    func typingAttributesHaveInlineIntentOrTrait(
        _ attrs: AttributeContainer,
        intent: InlinePresentationIntent
    ) -> Bool {
        if (attrs.inlinePresentationIntent ?? []).contains(intent) {
            return true
        }
        return fontFromAttributes(attrs).map { font in
            fontHasTrait(font, for: intent)
        } ?? false
    }

    private func runHasInlineIntentOrTrait(
        _ run: AttributedString.Runs.Run,
        intent: InlinePresentationIntent
    ) -> Bool {
        if (run.inlinePresentationIntent ?? []).contains(intent) {
            return true
        }
        return fontFromRun(run).map { font in
            fontHasTrait(font, for: intent)
        } ?? false
    }

    private func fontFromRun(_ run: AttributedString.Runs.Run) -> PlatformFont? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        return platformFont(from: sample)
    }

    private func fontFromAttributes(_ attrs: AttributeContainer) -> PlatformFont? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(attrs)
        return platformFont(from: sample)
    }

    private func platformFont(from text: AttributedString) -> PlatformFont? {
        let bridged: NSAttributedString
        #if os(macOS)
        bridged = (try? NSAttributedString(text, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(text)
        #else
        bridged = NSAttributedString(text)
        #endif
        guard bridged.length > 0 else { return nil }
        return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as? PlatformFont
    }

    private func fontHasTrait(
        _ font: PlatformFont,
        for intent: InlinePresentationIntent
    ) -> Bool {
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
}
