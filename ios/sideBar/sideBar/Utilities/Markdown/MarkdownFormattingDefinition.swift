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
