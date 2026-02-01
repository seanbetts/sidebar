import Foundation
import SwiftUI

// MARK: - BlockKind

@available(iOS 26.0, macOS 26.0, *)
public enum BlockKind: String, Codable, Hashable, Sendable {
    case paragraph
    case blankLine
    case heading1
    case heading2
    case heading3
    case heading4
    case heading5
    case heading6
    case bulletList
    case orderedList
    case taskUnchecked
    case taskChecked
    case blockquote
    case codeBlock
    case horizontalRule
    case gallery
    case imageCaption
    case htmlBlock
}

// MARK: - Attribute Keys

@available(iOS 26.0, macOS 26.0, *)
public enum BlockKindAttribute: CodableAttributedStringKey {
    public typealias Value = BlockKind
    public static let name = "sideBar.blockKind"

    public static var inheritedByAddedText: Bool { false }
    public static var runBoundaries: AttributedString.AttributeRunBoundaries? { .paragraph }
}

@available(iOS 26.0, macOS 26.0, *)
public enum ListDepthAttribute: CodableAttributedStringKey {
    public typealias Value = Int
    public static let name = "sideBar.listDepth"

    public static var inheritedByAddedText: Bool { false }
    public static var runBoundaries: AttributedString.AttributeRunBoundaries? { .paragraph }
}

@available(iOS 26.0, macOS 26.0, *)
public enum CodeLanguageAttribute: CodableAttributedStringKey {
    public typealias Value = String
    public static let name = "sideBar.codeLanguage"

    public static var inheritedByAddedText: Bool { false }
    public static var runBoundaries: AttributedString.AttributeRunBoundaries? { .paragraph }
}

@available(iOS 26.0, macOS 26.0, *)
public enum InlineMarkerAttribute: CodableAttributedStringKey {
    public typealias Value = Bool
    public static let name = "sideBar.inlineMarker"

    public static var inheritedByAddedText: Bool { false }
}

@available(iOS 26.0, macOS 26.0, *)
public enum ListMarkerAttribute: CodableAttributedStringKey {
    public typealias Value = Bool
    public static let name = "sideBar.listMarker"

    public static var inheritedByAddedText: Bool { false }
}

@available(iOS 26.0, macOS 26.0, *)
public struct ImageInfo: Codable, Hashable, Sendable {
    public let url: URL
    public let altText: String

    public init(url: URL, altText: String) {
        self.url = url
        self.altText = altText
    }
}

@available(iOS 26.0, macOS 26.0, *)
public enum ImageInfoAttribute: CodableAttributedStringKey {
    public typealias Value = ImageInfo
    public static let name = "sideBar.imageInfo"

    public static var inheritedByAddedText: Bool { false }
}

// MARK: - Attribute Scope

@available(iOS 26.0, macOS 26.0, *)
public extension AttributeScopes {
    struct MarkdownEditorAttributes: AttributeScope {
        public let blockKind: BlockKindAttribute
        public let listDepth: ListDepthAttribute
        public let codeLanguage: CodeLanguageAttribute
        public let inlineMarker: InlineMarkerAttribute
        public let listMarker: ListMarkerAttribute
        public let imageInfo: ImageInfoAttribute
        public let presentationIntent: AttributeScopes.FoundationAttributes.PresentationIntentAttribute
        public let listItemDelimiter: AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute
        public let foundation: AttributeScopes.FoundationAttributes
        public let swiftUI: AttributeScopes.SwiftUIAttributes
    }

    var markdownEditor: MarkdownEditorAttributes.Type {
        MarkdownEditorAttributes.self
    }
}

// MARK: - Dynamic Lookup

@available(iOS 26.0, macOS 26.0, *)
public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.MarkdownEditorAttributes, T>
    ) -> T {
        self[T.self]
    }
}

// MARK: - Convenience Accessors

@available(iOS 26.0, macOS 26.0, *)
public extension AttributedString {
    func blockKind(in range: Range<Index>) -> BlockKind? {
        var result: BlockKind?
        for run in self[range].runs {
            guard let kind = run.blockKind else { continue }
            if result == nil {
                result = kind
            } else if result != kind {
                return nil
            }
        }
        return result
    }
}
