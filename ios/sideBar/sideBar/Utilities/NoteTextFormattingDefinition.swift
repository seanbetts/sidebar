import Foundation
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
public struct NoteTextFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.NoteTextEditorAttributes

    public init() {}

    public var body: some AttributedTextFormattingDefinition<Scope> {
        // We intentionally normalize note text structure in `constrainDocument` where we can
        // reason across paragraph boundaries and related attributes together.
        // These value constraints are placeholders required by the definition protocol.
        PresentationIntentConstraint()
        ListItemDelimiterConstraint()
    }

    public func constrainedDocument(_ text: AttributedString) -> AttributedString {
        var constrained = text
        constrainDocument(&constrained)
        return constrained
    }

    public func constrainDocument(_ text: inout AttributedString) {
        for range in paragraphRanges(in: text) where !range.isEmpty {
            constrainParagraph(in: &text, range: range)
        }
    }

    private func constrainParagraph(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        let existingPresentationIntent = presentationIntent(in: text, range: range)
        let blockKind = normalizedBlockKind(text.blockKind(in: range))
        text[range].blockKind = blockKind

        if isListBlock(blockKind) {
            let normalizedDepth = max(1, text[range].listDepth ?? 1)
            text[range].listDepth = normalizedDepth
            text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = normalizedListDelimiter(
                for: blockKind,
                current: text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self]
            )
        } else {
            text[range].listDepth = nil
            text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
        }

        if blockKind != .codeBlock {
            text[range].codeLanguage = nil
        }

        constrainVisualAttributes(in: &text, range: range)

        // V2 path does not rely on hidden marker runs.
        text[range].inlineMarker = nil
        text[range].listMarker = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = normalizedPresentationIntent(
            for: blockKind,
            listDepth: text[range].listDepth,
            existingIntent: existingPresentationIntent,
            codeLanguage: text[range].codeLanguage
        )
    }

    private func paragraphRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var lineStart = text.startIndex
        var current = text.startIndex

        while current < text.endIndex {
            if text.characters[current].isNewline {
                ranges.append(lineStart..<current)
                lineStart = text.index(afterCharacter: current)
                current = lineStart
            } else {
                current = text.index(afterCharacter: current)
            }
        }

        if lineStart <= text.endIndex {
            ranges.append(lineStart..<text.endIndex)
        }

        return ranges
    }

    private func constrainVisualAttributes(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].font = nil
        text[range].foregroundColor = nil
        text[range].backgroundColor = nil
        text[range].paragraphStyle = nil
#if os(iOS)
        text[range][AttributeScopes.UIKitAttributes.FontAttribute.self] = nil
        text[range][AttributeScopes.UIKitAttributes.ForegroundColorAttribute.self] = nil
        text[range][AttributeScopes.UIKitAttributes.BackgroundColorAttribute.self] = nil
#elseif os(macOS)
        text[range][AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = nil
        text[range][AttributeScopes.AppKitAttributes.BackgroundColorAttribute.self] = nil
#endif
    }

    private func normalizedBlockKind(_ blockKind: BlockKind?) -> BlockKind {
        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
             .paragraph, .blankLine, .bulletList, .orderedList, .taskUnchecked, .taskChecked,
             .blockquote, .codeBlock, .horizontalRule, .gallery, .imageCaption, .htmlBlock:
            return blockKind ?? .paragraph
        case .none:
            return .paragraph
        @unknown default:
            return .paragraph
        }
    }

    private func isListBlock(_ blockKind: BlockKind) -> Bool {
        switch blockKind {
        case .bulletList, .orderedList, .taskUnchecked, .taskChecked:
            return true
        default:
            return false
        }
    }

    private func normalizedListDelimiter(for blockKind: BlockKind, current: Character?) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskUnchecked:
            return "☐"
        case .taskChecked:
            return "☑"
        case .orderedList:
            return nil
        default:
            return current
        }
    }

    private func normalizedPresentationIntent(
        for blockKind: BlockKind,
        listDepth: Int?,
        existingIntent: PresentationIntent?,
        codeLanguage: String?
    ) -> PresentationIntent {
        let quoteDepth = blockquoteDepth(in: existingIntent)
        if let level = headingLevel(for: blockKind) {
            return scopedPresentationIntent(
                kind: .header(level: level),
                identity: level,
                quoteDepth: quoteDepth
            )
        }

        if let listIntent = listPresentationIntent(
            for: blockKind,
            listDepth: listDepth,
            quoteDepth: quoteDepth,
            existingIntent: existingIntent
        ) {
            return listIntent
        }

        switch blockKind {
        case .blockquote:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                quoteDepth: max(1, quoteDepth)
            )
        case .codeBlock:
            return scopedPresentationIntent(
                kind: .codeBlock(languageHint: codeLanguage),
                identity: 1,
                quoteDepth: quoteDepth
            )
        case .horizontalRule:
            return scopedPresentationIntent(
                kind: .thematicBreak,
                identity: 1,
                quoteDepth: quoteDepth
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                quoteDepth: quoteDepth
            )
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
             .bulletList, .orderedList, .taskUnchecked, .taskChecked:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                quoteDepth: quoteDepth
            )
        @unknown default:
            return scopedPresentationIntent(
                kind: .paragraph,
                identity: 1,
                quoteDepth: quoteDepth
            )
        }
    }

    private func headingLevel(for blockKind: BlockKind) -> Int? {
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

    private func listPresentationIntent(
        for blockKind: BlockKind,
        listDepth: Int?,
        quoteDepth: Int,
        existingIntent: PresentationIntent?
    ) -> PresentationIntent? {
        let listKind: PresentationIntent.Kind
        switch blockKind {
        case .orderedList:
            listKind = .orderedList
        case .bulletList, .taskChecked, .taskUnchecked:
            listKind = .unorderedList
        default:
            return nil
        }

        let depth = max(1, listDepth ?? 1)
        let listIdentity = existingListIdentity(in: existingIntent) ?? depth
        let listOrdinal = blockKind == .orderedList ? (existingListOrdinal(in: existingIntent) ?? 1) : 1
        let quoteIntent = blockquoteIntent(depth: quoteDepth)
        let listIntent: PresentationIntent
        if let quoteIntent {
            listIntent = PresentationIntent(listKind, identity: listIdentity, parent: quoteIntent)
        } else {
            listIntent = PresentationIntent(listKind, identity: listIdentity)
        }
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: listOrdinal),
            identity: existingListItemIdentity(in: existingIntent) ?? (listIdentity * 1000 + listOrdinal),
            parent: listIntent
        )
        return PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
    }

    private func presentationIntent(
        in text: AttributedString,
        range: Range<AttributedString.Index>
    ) -> PresentationIntent? {
        for run in text[range].runs {
            if let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] {
                return intent
            }
        }
        return nil
    }

    private func blockquoteDepth(in intent: PresentationIntent?) -> Int {
        guard let intent else { return 0 }
        return intent.components.reduce(into: 0) { result, component in
            if case .blockQuote = component.kind {
                result += 1
            }
        }
    }

    private func existingListIdentity(in intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            switch component.kind {
            case .orderedList, .unorderedList:
                return component.identity
            default:
                break
            }
        }
        return nil
    }

    private func existingListItemIdentity(in intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .listItem = component.kind {
                return component.identity
            }
        }
        return nil
    }

    private func existingListOrdinal(in intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .listItem(let ordinal) = component.kind {
                return ordinal
            }
        }
        return nil
    }

    private func scopedPresentationIntent(
        kind: PresentationIntent.Kind,
        identity: Int,
        quoteDepth: Int
    ) -> PresentationIntent {
        if let quoteIntent = blockquoteIntent(depth: quoteDepth) {
            return PresentationIntent(kind, identity: identity, parent: quoteIntent)
        }
        return PresentationIntent(kind, identity: identity)
    }

    private func blockquoteIntent(depth: Int) -> PresentationIntent? {
        guard depth > 0 else { return nil }
        var current = PresentationIntent(.blockQuote, identity: 1)
        guard depth > 1 else { return current }
        for level in 2...depth {
            current = PresentationIntent(.blockQuote, identity: level, parent: current)
        }
        return current
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct PresentationIntentConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.PresentationIntentAttribute

    func constrain(_ container: inout Attributes) {
        // Paragraph-level normalization happens in NoteTextFormattingDefinition.constrainDocument.
        _ = container
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ListItemDelimiterConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute

    func constrain(_ container: inout Attributes) {
        // Paragraph-level normalization happens in NoteTextFormattingDefinition.constrainDocument.
        _ = container
    }
}
