import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct MarkdownFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.MarkdownEditorAttributes

    public init() {}

    public var body: some AttributedTextFormattingDefinition<Scope> {
        AttributedTextFormatting.EmptyDefinition()
    }
}
