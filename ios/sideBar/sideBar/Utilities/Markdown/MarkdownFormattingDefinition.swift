import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.MarkdownEditorAttributes

    public init() {}

    public var valueConstraints: [any AttributedTextValueConstraint] {
        [
            CodeBlockFontConstraint(),
            HeadingFontConstraint()
        ]
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct CodeBlockFontConstraint: AttributedTextValueConstraint {
    func contains(_ value: Font?) -> Bool {
        true
    }

    func constrain(_ value: Font?) -> Font? {
        value
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct HeadingFontConstraint: AttributedTextValueConstraint {
    func contains(_ value: Font?) -> Bool {
        true
    }

    func constrain(_ value: Font?) -> Font? {
        value
    }
}
