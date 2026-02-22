import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.MarkdownEditorAttributes

    public init() {}

    public var body: some AttributedTextFormattingDefinition<Scope> {
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

        // V2 path does not rely on hidden marker runs.
        text[range].inlineMarker = nil
        text[range].listMarker = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = normalizedPresentationIntent(
            for: blockKind,
            listDepth: text[range].listDepth
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
        listDepth: Int?
    ) -> PresentationIntent {
        if let level = headingLevel(for: blockKind) {
            return PresentationIntent(.header(level: level), identity: level)
        }

        if let listIntent = listPresentationIntent(for: blockKind, listDepth: listDepth) {
            return listIntent
        }

        switch blockKind {
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            return PresentationIntent(.paragraph, identity: 1, parent: quoteIntent)
        case .codeBlock:
            return PresentationIntent(.codeBlock(languageHint: nil), identity: 1)
        case .horizontalRule:
            return PresentationIntent(.thematicBreak, identity: 1)
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            return PresentationIntent(.paragraph, identity: 1)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6,
             .bulletList, .orderedList, .taskUnchecked, .taskChecked:
            return PresentationIntent(.paragraph, identity: 1)
        @unknown default:
            return PresentationIntent(.paragraph, identity: 1)
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

    private func listPresentationIntent(for blockKind: BlockKind, listDepth: Int?) -> PresentationIntent? {
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
        let listIntent = PresentationIntent(listKind, identity: depth)
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: 1),
            identity: depth * 1000 + 1,
            parent: listIntent
        )
        return PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct PresentationIntentConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.MarkdownEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.PresentationIntentAttribute

    func constrain(_ container: inout Attributes) {
        _ = container
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ListItemDelimiterConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.MarkdownEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute

    func constrain(_ container: inout Attributes) {
        _ = container
    }
}
