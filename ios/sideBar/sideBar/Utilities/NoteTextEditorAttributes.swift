import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public extension AttributeScopes {
    struct NoteTextEditorAttributes: AttributeScope {
        public let foundation: AttributeScopes.FoundationAttributes
        public let swiftUI: AttributeScopes.SwiftUIAttributes
        #if os(iOS)
        public let uiKit: AttributeScopes.UIKitAttributes
        #elseif os(macOS)
        public let appKit: AttributeScopes.AppKitAttributes
        #endif
    }

    var noteTextEditor: NoteTextEditorAttributes.Type {
        NoteTextEditorAttributes.self
    }
}

@available(iOS 26.0, macOS 26.0, *)
public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.NoteTextEditorAttributes, T>
    ) -> T {
        self[T.self]
    }
}
