import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public enum NoteTextBlockAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    public typealias Value = String
    public typealias ObjectiveCValue = NSString

    public static let name = "ai.sidebar.notes.block"
    public static let unorderedListRawValue = NotesSemanticDocument.BlockType.unorderedList.rawValue

    public static func objectiveCValue(for value: String) throws -> NSString {
        value as NSString
    }

    public static func value(for object: NSString) throws -> String {
        object as String
    }

    static func blockType(from rawValue: String?) -> NotesSemanticDocument.BlockType? {
        guard let rawValue else { return nil }
        return NotesSemanticDocument.BlockType(rawValue: rawValue)
    }
}

@available(iOS 26.0, macOS 26.0, *)
public enum NoteTextStructuralBoundaryAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    public typealias Value = Bool
    public typealias ObjectiveCValue = NSNumber

    public static let name = "ai.sidebar.notes.structural-boundary"

    public static func objectiveCValue(for value: Bool) throws -> NSNumber {
        NSNumber(value: value)
    }

    public static func value(for object: NSNumber) throws -> Bool {
        object.boolValue
    }
}

@available(iOS 26.0, macOS 26.0, *)
public enum NoteTextChecklistCompletionAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    public typealias Value = Bool
    public typealias ObjectiveCValue = NSNumber

    public static let name = "ai.sidebar.notes.checklist-completion"

    public static func objectiveCValue(for value: Bool) throws -> NSNumber {
        NSNumber(value: value)
    }

    public static func value(for object: NSNumber) throws -> Bool {
        object.boolValue
    }
}

@available(iOS 26.0, macOS 26.0, *)
public extension AttributeScopes {
    struct NoteTextEditorAttributes: AttributeScope {
        public let foundation: AttributeScopes.FoundationAttributes
        public let swiftUI: AttributeScopes.SwiftUIAttributes
        public let noteBlock: NoteTextBlockAttribute
        public let noteStructuralBoundary: NoteTextStructuralBoundaryAttribute
        public let noteChecklistCompletion: NoteTextChecklistCompletionAttribute
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
