import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct NoteTextFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.NoteTextEditorAttributes

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
        for run in text.runs {
            let range = run.range
            constrainInlineFormatting(in: &text, range: range)
            clearUnsupportedEditorAttributes(in: &text, range: range)
        }
    }

    private func constrainInlineFormatting(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        var intents = text[range].inlinePresentationIntent ?? []
        intents.remove(.code)
        text[range].inlinePresentationIntent = intents.isEmpty ? nil : intents

        if text[range].underlineStyle != nil {
            text[range].underlineStyle = .single
        }
        text[range].strikethroughStyle = nil
    }

    private func clearUnsupportedEditorAttributes(
        in text: inout AttributedString,
        range: Range<AttributedString.Index>
    ) {
        text[range].blockKind = nil
        text[range].listDepth = nil
        text[range].codeLanguage = nil
        text[range].inlineMarker = nil
        text[range].listMarker = nil
        text[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
        text[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct PresentationIntentConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.PresentationIntentAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private struct ListItemDelimiterConstraint: AttributedTextValueConstraint {
    typealias Scope = AttributeScopes.NoteTextEditorAttributes
    typealias AttributeKey = AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute

    func constrain(_ container: inout Attributes) {
        container[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
    }
}
