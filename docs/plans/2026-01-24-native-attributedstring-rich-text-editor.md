# Native AttributedString Rich Text Editor

**Created:** 2026-01-24
**Platform:** iOS 26+ / macOS 26+
**Status:** Implemented (testing pending)

---

## Progress Tracking

### Phase 1: Foundation
- [x] **1.1** Create `MarkdownEditorAttributes.swift` - Custom attribute scope
  - [x] Define `BlockKind` enum with all block types
  - [x] Create `BlockKindAttribute` with `inheritedByAddedText`, `invalidationConditions`, `runBoundaries`
  - [x] Create `ListDepthAttribute` for nested lists
  - [x] Create `CodeLanguageAttribute` for fenced code blocks
  - [x] Add `AttributeScopes.MarkdownEditorAttributes` extension
  - [x] Add `AttributeDynamicLookup` extension for dot syntax
  - [x] Add convenience accessors on `AttributedString`
- [x] **1.2** Create `MarkdownFormattingDefinition.swift`
  - [x] Implement `AttributedTextFormattingDefinition` protocol
  - [x] Add value constraints for code blocks and headings

### Phase 2: Markdown Import
- [x] **2.1** Add swift-markdown package dependency
- [x] **2.2** Create `MarkdownImporter.swift`
  - [x] Implement `MarkupWalker` for document traversal
  - [x] Handle paragraphs with block kind attribute
  - [x] Handle headings 1-6 with font styling
  - [x] Handle unordered lists with depth tracking
  - [x] Handle ordered lists with depth tracking
  - [x] Handle task lists (checked/unchecked)
  - [x] Handle blockquotes with depth tracking
  - [x] Handle fenced code blocks with language
  - [x] Handle thematic breaks (horizontal rules)
  - [x] Handle inline: bold, italic, strikethrough, code, links

### Phase 3: Markdown Export
- [x] **3.1** Create `MarkdownExporter.swift`
  - [x] Split attributed string by newlines
  - [x] Generate block prefixes from `blockKind` attribute
  - [x] Handle code block fence generation
  - [x] Export inline formatting (bold, italic, code, strike, links)
  - [x] Handle list indentation from `listDepth`

### Phase 4: Editor ViewModel
- [x] **4.1** Create `NativeMarkdownEditorViewModel.swift`
  - [x] Published properties: `attributedContent`, `selection`, `isReadOnly`, `hasUnsavedChanges`
  - [x] `loadMarkdown()` using importer
  - [x] `currentMarkdown()` using exporter
  - [x] Inline formatting: `toggleInlineIntent()`, `toggleStrikethrough()`
  - [x] Block formatting: `setBlockKind()`, `findParagraphRange()`
  - [x] Insert operations: `insertLink()`, `insertHorizontalRule()`
  - [x] Autosave with debounce

### Phase 5: SwiftUI Editor View
- [x] **5.1** Create `NativeMarkdownEditorView.swift`
  - [x] `TextEditor` with `AttributedString` binding
  - [x] Apply `MarkdownFormattingDefinition`
  - [x] Formatting toolbar with all buttons
  - [x] Proper spacing and max width constraints

### Phase 6: Live Shortcuts
- [x] **6.1** Create `MarkdownShortcutProcessor.swift`
  - [x] Block shortcuts: `# `, `## `, `- `, `1. `, `> `, `- [ ] `, etc.
  - [x] Inline shortcuts: `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`
  - [x] Link shortcuts: `[text](url)`
  - [x] Update selection after consuming shortcuts

### Phase 7: Integration
- [x] **7.1** Create `NotesEditorViewModel+Native.swift`
  - [x] `makeNativeEditorViewModel()` factory method
  - [x] `syncFromNativeEditor()` for saving changes
- [x] **7.2** Update note editor view to use native editor
  - [x] Add `@available` check for iOS 26
  - [x] Feature flag for gradual rollout
  - [x] Fallback to SideBarMarkdown

### Phase 8: Display Parity
- [x] **8.1** Typography and inline styles
  - [x] Base body font size matches `SideBarMarkdown` (16)
  - [x] Inline code font size and background match `SideBarMarkdown`
  - [x] Strikethrough color matches `SideBarMarkdown`
- [x] **8.2** Block presentation
  - [x] Headings use presentation intent for consistent spacing
  - [x] Lists render bullets/ordinals using presentation intent + delimiters
  - [x] Blockquotes render with appropriate intent
  - [x] Thematic breaks render with intent
- [x] **8.3** Code blocks and tables
  - [x] Code blocks visually match `SideBarMarkdown` (padding/border/background)
  - [x] Tables parse and render with basic styling
- [x] **8.4** Markdown syntax visibility
  - [x] Show block prefixes only on the caret line

### Testing
- [x] Unit tests for `MarkdownImporter`
  - [x] Test each block type
  - [x] Test each inline style
  - [x] Test nested structures
  - [x] Test frontmatter + caption/gallery handling
- [x] Unit tests for `MarkdownExporter`
  - [x] Test each block type
  - [x] Test each inline style
  - [x] Test frontmatter + caption/gallery handling
- [x] Round-trip tests
  - [x] Import → Export → Import produces equivalent result
- [ ] Integration tests
  - [ ] Load note → Edit → Save → Reload preserves formatting
- [ ] UI tests
  - [ ] Toolbar buttons apply formatting
  - [ ] Keyboard shortcuts work

---

## Executive Summary

This plan implements a native SwiftUI rich text editing experience using iOS 26/macOS 26's new `TextEditor` support for `AttributedString`. Users edit styled text (bold, italic, headings, lists, etc.) while the canonical storage format remains Markdown. The system "consumes" Markdown syntax as the user types (e.g., typing `**bold**` becomes styled bold text with the asterisks removed).

### Goals
1. Replace the current read-only notes view with a native SwiftUI editor
2. Maintain Markdown as the canonical storage format for server sync
3. Provide rich text editing with formatting toolbar support
4. Implement semantic block attributes for reliable round-trip conversion
5. Support all current Markdown features: headings, bold, italic, strikethrough, code, lists, task lists, blockquotes, links

### Plan Alignment with Current iOS Markdown
- Use `SideBarMarkdown` as the non-iOS 26 fallback renderer (read-only).
- Treat `MarkdownFormatting` as deprecated; do not use it in the new pipeline.
- Mirror `SideBarMarkdown` typography and spacing when applying formatting in the importer.
- Hide frontmatter in the editor: strip on import, preserve on export (store it in view model state).
- Preserve sideBar-specific markdown conventions: `^caption:` lines and `<figure class="image-gallery">…</figure>` blocks should round-trip without loss.

---

## Background: iOS 26 AttributedString APIs

### What's New in iOS 26

iOS 26 introduces native rich text editing in SwiftUI's `TextEditor`:

```swift
// Before iOS 26: String only
TextEditor(text: $plainString)

// iOS 26+: AttributedString with selection
TextEditor(text: $attributedString, selection: $selection)
```

### Key New Types

#### 1. AttributedTextSelection
Represents text selection in the editor. Uses `RangeSet` instead of `Range` to handle bidirectional text:

```swift
@State private var selection = AttributedTextSelection()

// Get selected indices
let indices: RangeSet<AttributedString.Index> = selection.indices(in: text)

// Get attributes at selection
let attrs = selection.attributes(in: text)

// Get typing attributes (what new text will have)
let typingAttrs = selection.typingAttributes(in: text)
```

#### 2. AttributedTextFormattingDefinition Protocol
Defines which attributes your editor supports and constrains their values:

```swift
struct MarkdownFormattingDefinition: AttributedTextFormattingDefinition {
    // Limit which attributes can be applied
    typealias Scope = MarkdownEditorAttributes

    // Optionally constrain values
    var valueConstraints: [any AttributedTextValueConstraint] {
        [IngredientsAreGreenConstraint()]
    }
}
```

#### 3. Custom AttributedStringKey
Define semantic attributes that survive round-trip conversion:

```swift
enum BlockKindAttribute: CodableAttributedStringKey {
    typealias Value = BlockKind
    static let name = "sideBar.blockKind"

    // NEW in iOS 26: Control inheritance behavior
    static var inheritedByAddedText: Bool { false }

    // NEW in iOS 26: Auto-remove when conditions met
    static var invalidationConditions: InvalidationConditions { [.textChanged] }

    // NEW in iOS 26: Constrain to paragraph boundaries
    static var runBoundaries: AttributeRunBoundaries { .paragraph }
}
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SwiftUI TextEditor                           │
│              (AttributedString + Selection binding)             │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                 MarkdownEditorViewModel                         │
│  - attributedContent: AttributedString                          │
│  - selection: AttributedTextSelection                           │
│  - Handles formatting commands, live shortcut consumption       │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│              Translation Layer                                   │
│  ┌─────────────────┐    ┌─────────────────┐                     │
│  │ MarkdownImporter│    │MarkdownExporter │                     │
│  │ (MD → AttrStr)  │    │(AttrStr → MD)   │                     │
│  └─────────────────┘    └─────────────────┘                     │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│                    NotesStore                                    │
│              (Markdown String ↔ Server API)                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Foundation - Custom Attribute Scope

**Goal:** Define the semantic attributes that will be attached to text.

#### 1.1 Create MarkdownEditorAttributes.swift

```swift
// ios/sideBar/sideBar/Utilities/Markdown/MarkdownEditorAttributes.swift

import Foundation
import SwiftUI

// MARK: - Block Kind Enum

/// Represents the semantic type of a paragraph/block
public enum BlockKind: String, Codable, Hashable, Sendable {
    case paragraph
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
}

// MARK: - Block Kind Attribute Key

/// Semantic block-level attribute that identifies what kind of Markdown block this is.
/// This attribute is NOT inherited by new text and is invalidated when text changes.
public enum BlockKindAttribute: CodableAttributedStringKey {
    public typealias Value = BlockKind
    public static let name = "sideBar.blockKind"

    // Block kinds should not be inherited when user types new text
    public static var inheritedByAddedText: Bool { false }

    // Block kind should be invalidated when the line's text changes
    // (e.g., removing all text from a heading should reset to paragraph)
    public static var invalidationConditions: InvalidationConditions { [.textChanged] }

    // Block attributes apply to entire paragraphs
    public static var runBoundaries: AttributeRunBoundaries { .paragraph }
}

// MARK: - List Depth Attribute Key

/// Tracks nesting depth for lists (1-based)
public enum ListDepthAttribute: CodableAttributedStringKey {
    public typealias Value = Int
    public static let name = "sideBar.listDepth"

    public static var inheritedByAddedText: Bool { false }
    public static var invalidationConditions: InvalidationConditions { [.textChanged] }
    public static var runBoundaries: AttributeRunBoundaries { .paragraph }
}

// MARK: - Code Language Attribute Key

/// For fenced code blocks, tracks the language identifier
public enum CodeLanguageAttribute: CodableAttributedStringKey {
    public typealias Value = String
    public static let name = "sideBar.codeLanguage"

    public static var inheritedByAddedText: Bool { false }
    public static var invalidationConditions: InvalidationConditions { [.textChanged] }
    public static var runBoundaries: AttributeRunBoundaries { .paragraph }
}

// MARK: - Attribute Scope Extension

/// Custom attribute scope for sideBar markdown editor
public extension AttributeScopes {
    struct MarkdownEditorAttributes: AttributeScope {
        // Block-level semantic attributes
        public let blockKind: BlockKindAttribute
        public let listDepth: ListDepthAttribute
        public let codeLanguage: CodeLanguageAttribute

        // Include standard Foundation attributes we need
        public let foundation: AttributeScopes.FoundationAttributes

        // Include SwiftUI attributes for styling
        public let swiftUI: AttributeScopes.SwiftUIAttributes
    }

    var markdownEditor: MarkdownEditorAttributes.Type {
        MarkdownEditorAttributes.self
    }
}

// MARK: - AttributeDynamicLookup Extension

public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.MarkdownEditorAttributes, T>
    ) -> T {
        self[T.self]
    }
}

// MARK: - Convenience Accessors

public extension AttributedString {
    /// Get the block kind at a specific index
    func blockKind(at index: Index) -> BlockKind? {
        self[index].blockKind
    }

    /// Get the block kind for a range (returns nil if mixed)
    func blockKind(in range: Range<Index>) -> BlockKind? {
        var result: BlockKind?
        for run in self[range].runs {
            guard let kind = run.blockKind else { continue }
            if result == nil {
                result = kind
            } else if result != kind {
                return nil // Mixed block kinds
            }
        }
        return result
    }
}
```

#### 1.2 Create MarkdownFormattingDefinition.swift

```swift
// ios/sideBar/sideBar/Utilities/Markdown/MarkdownFormattingDefinition.swift

import Foundation
import SwiftUI

/// Defines the formatting capabilities of the sideBar markdown editor.
/// This restricts formatting to only Markdown-expressible attributes.
public struct MarkdownFormattingDefinition: AttributedTextFormattingDefinition {
    public typealias Scope = AttributeScopes.MarkdownEditorAttributes

    public init() {}

    /// Value constraints ensure certain invariants are maintained
    public var valueConstraints: [any AttributedTextValueConstraint] {
        [
            // Code blocks use monospace font
            CodeBlockFontConstraint(),
            // Headings have appropriate font sizes
            HeadingFontConstraint()
        ]
    }
}

// MARK: - Value Constraints

/// Ensures code blocks always use monospace font
struct CodeBlockFontConstraint: AttributedTextValueConstraint {
    func contains(_ value: Font?) -> Bool {
        // Allow any font that's monospaced for code blocks
        return true
    }

    func constrain(_ value: Font?) -> Font? {
        // This would be called to adjust fonts in code blocks
        // For now, we handle this in our formatting logic
        return value
    }
}

/// Ensures headings have appropriate styling
struct HeadingFontConstraint: AttributedTextValueConstraint {
    func contains(_ value: Font?) -> Bool {
        return true
    }

    func constrain(_ value: Font?) -> Font? {
        return value
    }
}
```

### Phase 2: Markdown Import (Markdown → AttributedString)

**Goal:** Convert Markdown text to a semantically-attributed `AttributedString`.

#### 2.1 Add swift-markdown Dependency

Add to `Package.swift` or via Xcode's package manager:
```swift
.package(url: "https://github.com/apple/swift-markdown", from: "0.5.0")
```

#### 2.2 Create MarkdownImporter.swift

```swift
// ios/sideBar/sideBar/Utilities/Markdown/MarkdownImporter.swift

import Foundation
import Markdown
import SwiftUI

/// Converts Markdown source text to AttributedString with semantic attributes.
public struct MarkdownImporter {

    public init() {}

    /// Parse markdown and return attributed string with semantic block attributes
    public func attributedString(from markdown: String) -> AttributedString {
        let document = Document(parsing: markdown)
        var result = AttributedString()

        var walker = MarkdownToAttributedStringWalker()
        walker.visit(document)
        result = walker.result

        return result
    }
}

// MARK: - Markdown Walker

private struct MarkdownToAttributedStringWalker: MarkupWalker {
    var result = AttributedString()

    // Track context for nested structures
    private var listStack: [(ordered: Bool, depth: Int)] = []
    private var inCodeBlock = false
    private var codeBlockLanguage: String?
    private var blockquoteDepth = 0

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) -> () {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        var paragraphText = AttributedString()

        for child in paragraph.children {
            paragraphText.append(inlineAttributedString(for: child))
        }

        // Apply block kind
        if blockquoteDepth > 0 {
            paragraphText.blockKind = .blockquote
        } else {
            paragraphText.blockKind = .paragraph
        }

        // Apply paragraph styling
        paragraphText.font = .body

        result.append(paragraphText)
        result.append(AttributedString("\n"))
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        var headingText = AttributedString()

        for child in heading.children {
            headingText.append(inlineAttributedString(for: child))
        }

        // Set semantic block kind
        let blockKind: BlockKind
        let font: Font

        switch heading.level {
        case 1:
            blockKind = .heading1
            font = .system(.title, weight: .bold)
        case 2:
            blockKind = .heading2
            font = .system(.title2, weight: .semibold)
        case 3:
            blockKind = .heading3
            font = .system(.title3, weight: .semibold)
        case 4:
            blockKind = .heading4
            font = .system(.headline, weight: .semibold)
        case 5:
            blockKind = .heading5
            font = .system(.subheadline, weight: .semibold)
        default:
            blockKind = .heading6
            font = .system(.footnote, weight: .semibold)
        }

        headingText.blockKind = blockKind
        headingText.font = font

        result.append(headingText)
        result.append(AttributedString("\n"))
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        let depth = listStack.count + 1
        listStack.append((ordered: false, depth: depth))

        for item in unorderedList.listItems {
            visitListItem(item)
        }

        listStack.removeLast()
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> () {
        let depth = listStack.count + 1
        listStack.append((ordered: true, depth: depth))

        for item in orderedList.listItems {
            visitListItem(item)
        }

        listStack.removeLast()
    }

    mutating func visitListItem(_ listItem: ListItem) -> () {
        guard let context = listStack.last else { return }

        var itemText = AttributedString()

        // Check if this is a task list item
        if let checkbox = listItem.checkbox {
            let isChecked = checkbox == .checked

            for child in listItem.children {
                if let paragraph = child as? Paragraph {
                    for inline in paragraph.children {
                        itemText.append(inlineAttributedString(for: inline))
                    }
                }
            }

            itemText.blockKind = isChecked ? .taskChecked : .taskUnchecked
            itemText.listDepth = context.depth

            if isChecked {
                itemText.foregroundColor = .secondary
                itemText.strikethroughStyle = .single
            }
        } else {
            // Regular list item
            for child in listItem.children {
                if let paragraph = child as? Paragraph {
                    for inline in paragraph.children {
                        itemText.append(inlineAttributedString(for: inline))
                    }
                }
            }

            itemText.blockKind = context.ordered ? .orderedList : .bulletList
            itemText.listDepth = context.depth
        }

        itemText.font = .body
        result.append(itemText)
        result.append(AttributedString("\n"))
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        blockquoteDepth += 1

        for child in blockQuote.children {
            visit(child)
        }

        blockquoteDepth -= 1
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        var codeText = AttributedString(codeBlock.code)
        codeText.blockKind = .codeBlock
        codeText.font = .system(.body, design: .monospaced)
        codeText.backgroundColor = Color(.secondarySystemBackground)

        if let language = codeBlock.language, !language.isEmpty {
            codeText.codeLanguage = language
        }

        result.append(codeText)
        if !codeBlock.code.hasSuffix("\n") {
            result.append(AttributedString("\n"))
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        var hrText = AttributedString("───")
        hrText.blockKind = .horizontalRule
        hrText.foregroundColor = .secondary
        result.append(hrText)
        result.append(AttributedString("\n"))
    }

    // MARK: - Inline Elements

    private func inlineAttributedString(for markup: Markup) -> AttributedString {
        switch markup {
        case let text as Markdown.Text:
            return AttributedString(text.string)

        case let strong as Strong:
            var text = AttributedString()
            for child in strong.children {
                text.append(inlineAttributedString(for: child))
            }
            text.inlinePresentationIntent = .stronglyEmphasized
            return text

        case let emphasis as Emphasis:
            var text = AttributedString()
            for child in emphasis.children {
                text.append(inlineAttributedString(for: child))
            }
            text.inlinePresentationIntent = .emphasized
            return text

        case let strikethrough as Strikethrough:
            var text = AttributedString()
            for child in strikethrough.children {
                text.append(inlineAttributedString(for: child))
            }
            text.strikethroughStyle = .single
            return text

        case let inlineCode as InlineCode:
            var text = AttributedString(inlineCode.code)
            text.inlinePresentationIntent = .code
            text.font = .system(.body, design: .monospaced)
            text.backgroundColor = Color(.tertiarySystemBackground)
            return text

        case let link as Markdown.Link:
            var text = AttributedString()
            for child in link.children {
                text.append(inlineAttributedString(for: child))
            }
            if let destination = link.destination, let url = URL(string: destination) {
                text.link = url
                text.foregroundColor = .accentColor
            }
            return text

        case let softBreak as SoftBreak:
            return AttributedString(" ")

        case let lineBreak as LineBreak:
            return AttributedString("\n")

        default:
            // For any unhandled markup, try to get plain text
            var text = AttributedString()
            if let container = markup as? any Markup {
                for child in container.children {
                    text.append(inlineAttributedString(for: child))
                }
            }
            return text
        }
    }
}
```

### Phase 3: Markdown Export (AttributedString → Markdown)

**Goal:** Convert semantically-attributed `AttributedString` back to Markdown.

#### 3.1 Create MarkdownExporter.swift

```swift
// ios/sideBar/sideBar/Utilities/Markdown/MarkdownExporter.swift

import Foundation
import SwiftUI

/// Converts AttributedString with semantic attributes back to Markdown source.
public struct MarkdownExporter {

    public init() {}

    /// Export attributed string to markdown, using semantic block attributes
    public func markdown(from attributedString: AttributedString) -> String {
        var output: [String] = []

        // Split by paragraphs (newlines)
        let lines = attributedString.split(separator: "\n", omittingEmptySubsequences: false)

        var inCodeBlock = false
        var codeBlockLanguage: String?

        for line in lines {
            let lineStr = AttributedString(line)

            // Check block kind
            let blockKind = lineStr.runs.first?.blockKind ?? .paragraph

            // Handle code block transitions
            if blockKind == .codeBlock {
                if !inCodeBlock {
                    let lang = lineStr.runs.first?.codeLanguage ?? ""
                    output.append("```\(lang)")
                    inCodeBlock = true
                    codeBlockLanguage = lang
                }
                output.append(String(line.characters))
                continue
            } else if inCodeBlock {
                output.append("```")
                inCodeBlock = false
                codeBlockLanguage = nil
            }

            // Build the line with block prefix
            let prefix = blockPrefix(for: blockKind, listDepth: lineStr.runs.first?.listDepth ?? 1)
            let inlineMarkdown = exportInlineMarkdown(from: lineStr)

            output.append(prefix + inlineMarkdown)
        }

        // Close any open code block
        if inCodeBlock {
            output.append("```")
        }

        return output.joined(separator: "\n")
    }

    // MARK: - Block Prefixes

    private func blockPrefix(for blockKind: BlockKind, listDepth: Int) -> String {
        let indent = String(repeating: "  ", count: max(0, listDepth - 1))

        switch blockKind {
        case .paragraph:
            return ""
        case .heading1:
            return "# "
        case .heading2:
            return "## "
        case .heading3:
            return "### "
        case .heading4:
            return "#### "
        case .heading5:
            return "##### "
        case .heading6:
            return "###### "
        case .bulletList:
            return "\(indent)- "
        case .orderedList:
            return "\(indent)1. "
        case .taskUnchecked:
            return "\(indent)- [ ] "
        case .taskChecked:
            return "\(indent)- [x] "
        case .blockquote:
            return "> "
        case .codeBlock:
            return "" // Handled separately
        case .horizontalRule:
            return "---"
        }
    }

    // MARK: - Inline Export

    private func exportInlineMarkdown(from attributedString: AttributedString) -> String {
        var output = ""

        for run in attributedString.runs {
            let text = String(attributedString[run.range].characters)
            var wrapped = text

            // Check for inline presentation intent
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    wrapped = "**\(wrapped)**"
                }
                if intent.contains(.emphasized) {
                    wrapped = "*\(wrapped)*"
                }
                if intent.contains(.code) {
                    wrapped = "`\(wrapped)`"
                }
            }

            // Check for strikethrough
            if run.strikethroughStyle != nil {
                wrapped = "~~\(wrapped)~~"
            }

            // Check for link
            if let url = run.link {
                wrapped = "[\(text)](\(url.absoluteString))"
            }

            output += wrapped
        }

        return output
    }
}
```

### Phase 4: Editor View Model

**Goal:** Create a ViewModel that manages the AttributedString state, formatting commands, and live shortcut consumption.

#### 4.1 Create NativeMarkdownEditorViewModel.swift

```swift
// ios/sideBar/sideBar/ViewModels/NativeMarkdownEditorViewModel.swift

import Foundation
import SwiftUI
import Combine
import os

/// ViewModel for the native SwiftUI AttributedString-based markdown editor.
@MainActor
public final class NativeMarkdownEditorViewModel: ObservableObject {

    // MARK: - Published State

    /// The attributed string being edited
    @Published public var attributedContent: AttributedString = AttributedString()

    /// Current text selection
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()

    /// Whether the editor is in read-only mode
    @Published public var isReadOnly: Bool = false

    /// Whether there are unsaved changes
    @Published public var hasUnsavedChanges: Bool = false

    /// Error message to display
    @Published public var errorMessage: String?

    // MARK: - Private Properties

    private let importer = MarkdownImporter()
    private let exporter = MarkdownExporter()
    private let logger = Logger(subsystem: "sideBar", category: "NativeMarkdownEditor")

    private var saveTask: Task<Void, Never>?
    private var lastSavedContent: String = ""
    private let saveDebounceInterval: TimeInterval = 1.5

    private var contentCancellable: AnyCancellable?

    // MARK: - Initialization

    public init() {
        setupContentObserver()
    }

    private func setupContentObserver() {
        contentCancellable = $attributedContent
            .debounce(for: .seconds(saveDebounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAutosave()
            }
    }

    // MARK: - Public API

    /// Load markdown content into the editor
    public func loadMarkdown(_ markdown: String) {
        attributedContent = importer.attributedString(from: markdown)
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    /// Get the current content as markdown
    public func currentMarkdown() -> String {
        exporter.markdown(from: attributedContent)
    }

    /// Apply formatting to the current selection
    public func applyFormatting(_ formatting: MarkdownFormatting) {
        guard !isReadOnly else { return }

        switch formatting {
        case .bold:
            toggleInlineIntent(.stronglyEmphasized)
        case .italic:
            toggleInlineIntent(.emphasized)
        case .strikethrough:
            toggleStrikethrough()
        case .inlineCode:
            toggleInlineIntent(.code)
        case .heading(let level):
            setBlockKind(headingBlockKind(for: level))
        case .bulletList:
            setBlockKind(.bulletList)
        case .orderedList:
            setBlockKind(.orderedList)
        case .taskList:
            setBlockKind(.taskUnchecked)
        case .blockquote:
            setBlockKind(.blockquote)
        case .codeBlock:
            setBlockKind(.codeBlock)
        case .link(let url):
            insertLink(url: url)
        case .horizontalRule:
            insertHorizontalRule()
        }

        hasUnsavedChanges = true
    }

    // MARK: - Inline Formatting

    private func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let indices = selection.indices(in: attributedContent)

        if indices.isEmpty {
            // No selection - toggle for typing attributes
            var typingAttrs = selection.typingAttributes(in: attributedContent)
            let current = typingAttrs.inlinePresentationIntent ?? []

            if current.contains(intent) {
                typingAttrs.inlinePresentationIntent = current.subtracting(intent)
            } else {
                typingAttrs.inlinePresentationIntent = current.union(intent)
            }
            // Note: In real implementation, we'd update typing attributes
            return
        }

        // Has selection - toggle for selected text
        for range in indices.ranges {
            let currentIntent = attributedContent[range].runs.first?.inlinePresentationIntent ?? []

            if currentIntent.contains(intent) {
                attributedContent[range].inlinePresentationIntent = currentIntent.subtracting(intent)
            } else {
                attributedContent[range].inlinePresentationIntent = currentIntent.union(intent)
            }
        }
    }

    private func toggleStrikethrough() {
        let indices = selection.indices(in: attributedContent)

        for range in indices.ranges {
            let hasStrike = attributedContent[range].runs.first?.strikethroughStyle != nil

            if hasStrike {
                attributedContent[range].strikethroughStyle = nil
            } else {
                attributedContent[range].strikethroughStyle = .single
            }
        }
    }

    // MARK: - Block Formatting

    private func setBlockKind(_ kind: BlockKind) {
        let indices = selection.indices(in: attributedContent)

        // Find paragraph boundaries for selected range
        guard let firstIndex = indices.ranges.first?.lowerBound else { return }

        // Find the start of the current paragraph
        let paragraphRange = findParagraphRange(containing: firstIndex)

        // Check if already this kind - toggle off to paragraph
        let currentKind = attributedContent[paragraphRange].runs.first?.blockKind

        if currentKind == kind {
            attributedContent[paragraphRange].blockKind = .paragraph
            applyBlockStyling(for: .paragraph, in: paragraphRange)
        } else {
            attributedContent[paragraphRange].blockKind = kind
            applyBlockStyling(for: kind, in: paragraphRange)
        }
    }

    private func findParagraphRange(containing index: AttributedString.Index) -> Range<AttributedString.Index> {
        // Find backwards to newline or start
        var start = attributedContent.startIndex
        var current = index

        while current > attributedContent.startIndex {
            let prevIndex = attributedContent.index(beforeCharacter: current)
            if attributedContent.characters[prevIndex] == "\n" {
                start = current
                break
            }
            current = prevIndex
        }

        // Find forwards to newline or end
        var end = attributedContent.endIndex
        current = index

        while current < attributedContent.endIndex {
            if attributedContent.characters[current] == "\n" {
                end = current
                break
            }
            current = attributedContent.index(afterCharacter: current)
        }

        return start..<end
    }

    private func applyBlockStyling(for kind: BlockKind, in range: Range<AttributedString.Index>) {
        switch kind {
        case .heading1:
            attributedContent[range].font = .system(.title, weight: .bold)
        case .heading2:
            attributedContent[range].font = .system(.title2, weight: .semibold)
        case .heading3:
            attributedContent[range].font = .system(.title3, weight: .semibold)
        case .heading4:
            attributedContent[range].font = .system(.headline, weight: .semibold)
        case .heading5:
            attributedContent[range].font = .system(.subheadline, weight: .semibold)
        case .heading6:
            attributedContent[range].font = .system(.footnote, weight: .semibold)
        case .codeBlock:
            attributedContent[range].font = .system(.body, design: .monospaced)
            attributedContent[range].backgroundColor = Color(.secondarySystemBackground)
        case .blockquote:
            attributedContent[range].foregroundColor = .secondary
        case .taskChecked:
            attributedContent[range].strikethroughStyle = .single
            attributedContent[range].foregroundColor = .secondary
        default:
            attributedContent[range].font = .body
        }
    }

    private func headingBlockKind(for level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }

    // MARK: - Insert Operations

    private func insertLink(url: URL) {
        let indices = selection.indices(in: attributedContent)

        if indices.isEmpty {
            // Insert placeholder link
            var linkText = AttributedString("link")
            linkText.link = url
            linkText.foregroundColor = .accentColor

            // Insert at current position
            let position = selection.indices(in: attributedContent).ranges.first?.lowerBound ?? attributedContent.endIndex
            attributedContent.insert(linkText, at: position)
        } else {
            // Apply link to selection
            for range in indices.ranges {
                attributedContent[range].link = url
                attributedContent[range].foregroundColor = .accentColor
            }
        }
    }

    private func insertHorizontalRule() {
        var hr = AttributedString("\n───\n")
        hr.blockKind = .horizontalRule
        hr.foregroundColor = .secondary

        let position = selection.indices(in: attributedContent).ranges.first?.lowerBound ?? attributedContent.endIndex
        attributedContent.insert(hr, at: position)
    }

    // MARK: - Autosave

    private func scheduleAutosave() {
        let currentMarkdown = currentMarkdown()

        if currentMarkdown != lastSavedContent {
            hasUnsavedChanges = true
            // Trigger save via delegate/callback
            // In production, this would call NotesStore.applyEditorUpdate
        }
    }
}

// MARK: - Formatting Enum

public enum MarkdownFormatting {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case heading(level: Int)
    case bulletList
    case orderedList
    case taskList
    case blockquote
    case codeBlock
    case link(URL)
    case horizontalRule
}
```

### Phase 5: SwiftUI Editor View

**Goal:** Create the SwiftUI view that uses the native `TextEditor` with `AttributedString`.

#### 5.1 Create NativeMarkdownEditorView.swift

```swift
// ios/sideBar/sideBar/Views/Notes/NativeMarkdownEditorView.swift

import SwiftUI

/// Native SwiftUI markdown editor using iOS 26's AttributedString TextEditor.
@available(iOS 26.0, macOS 26.0, *)
public struct NativeMarkdownEditorView: View {
    @ObservedObject var viewModel: NativeMarkdownEditorViewModel
    let maxContentWidth: CGFloat
    let onSave: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        viewModel: NativeMarkdownEditorViewModel,
        maxContentWidth: CGFloat = 720,
        onSave: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.maxContentWidth = maxContentWidth
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Formatting toolbar
            if !viewModel.isReadOnly {
                formattingToolbar
            }

            // Editor
            ScrollView {
                TextEditor(
                    text: $viewModel.attributedContent,
                    selection: $viewModel.selection
                )
                .formattingDefinition(MarkdownFormattingDefinition())
                .scrollDisabled(true)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.md)
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Text formatting
                toolbarButton(systemImage: "bold", action: { viewModel.applyFormatting(.bold) })
                toolbarButton(systemImage: "italic", action: { viewModel.applyFormatting(.italic) })
                toolbarButton(systemImage: "strikethrough", action: { viewModel.applyFormatting(.strikethrough) })
                toolbarButton(systemImage: "chevron.left.slash.chevron.right", action: { viewModel.applyFormatting(.inlineCode) })

                Divider()
                    .frame(height: 20)

                // Block formatting
                toolbarButton(systemImage: "list.bullet", action: { viewModel.applyFormatting(.bulletList) })
                toolbarButton(systemImage: "list.number", action: { viewModel.applyFormatting(.orderedList) })
                toolbarButton(systemImage: "checkmark.square", action: { viewModel.applyFormatting(.taskList) })

                Divider()
                    .frame(height: 20)

                // Other
                toolbarButton(systemImage: "text.quote", action: { viewModel.applyFormatting(.blockquote) })
                toolbarButton(systemImage: "link", action: {
                    // In production, show link input dialog
                    if let url = URL(string: "https://") {
                        viewModel.applyFormatting(.link(url))
                    }
                })
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func toolbarButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
}
```

### Phase 6: Live Markdown Shortcut Consumption

**Goal:** Detect and consume typed Markdown syntax (e.g., `**bold**` → bold text).

#### 6.1 Create MarkdownShortcutProcessor.swift

```swift
// ios/sideBar/sideBar/Utilities/Markdown/MarkdownShortcutProcessor.swift

import Foundation
import SwiftUI

/// Processes typed markdown shortcuts and converts them to formatting.
/// Example: Typing "**bold**" converts to bold text with asterisks removed.
public struct MarkdownShortcutProcessor {

    // MARK: - Shortcut Patterns

    private static let inlinePatterns: [(pattern: String, suffix: String, intent: InlinePresentationIntent)] = [
        ("**", "**", .stronglyEmphasized),   // Bold
        ("__", "__", .stronglyEmphasized),   // Bold alt
        ("*", "*", .emphasized),              // Italic
        ("_", "_", .emphasized),              // Italic alt
        ("`", "`", .code),                    // Inline code
    ]

    private static let strikethroughPattern = ("~~", "~~")

    // Block patterns (at start of line)
    private static let blockPatterns: [(prefix: String, blockKind: BlockKind)] = [
        ("# ", .heading1),
        ("## ", .heading2),
        ("### ", .heading3),
        ("#### ", .heading4),
        ("##### ", .heading5),
        ("###### ", .heading6),
        ("- ", .bulletList),
        ("* ", .bulletList),
        ("+ ", .bulletList),
        ("> ", .blockquote),
        ("- [ ] ", .taskUnchecked),
        ("- [x] ", .taskChecked),
        ("- [X] ", .taskChecked),
    ]

    /// Process the attributed string after a change, consuming any completed shortcuts.
    /// Returns the modified attributed string and updated selection if changes were made.
    public static func processShortcuts(
        in text: inout AttributedString,
        selection: AttributedTextSelection,
        lastInsertedCharacter: Character?
    ) -> AttributedTextSelection? {

        // Get cursor position
        guard let cursorRange = selection.indices(in: text).ranges.first,
              cursorRange.isEmpty else {
            return nil // Only process when cursor, not selection
        }

        let cursorIndex = cursorRange.lowerBound

        // Check for block-level shortcuts at line start
        if let newSelection = processBlockShortcut(in: &text, at: cursorIndex) {
            return newSelection
        }

        // Check for inline shortcuts
        if let newSelection = processInlineShortcuts(in: &text, at: cursorIndex) {
            return newSelection
        }

        return nil
    }

    // MARK: - Block Shortcuts

    private static func processBlockShortcut(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> AttributedTextSelection? {

        // Find line start
        var lineStart = text.startIndex
        var current = cursorIndex

        while current > text.startIndex {
            let prev = text.index(beforeCharacter: current)
            if text.characters[prev] == "\n" {
                lineStart = current
                break
            }
            current = prev
        }

        // Get text from line start to cursor
        let lineRange = lineStart..<cursorIndex
        let lineText = String(text[lineRange].characters)

        // Check for block patterns
        for (prefix, blockKind) in blockPatterns {
            if lineText == prefix {
                // Remove the prefix and apply block formatting
                text.removeSubrange(lineRange)

                // Find the new line range after removal
                let newLineStart = lineStart
                var lineEnd = newLineStart
                while lineEnd < text.endIndex && text.characters[lineEnd] != "\n" {
                    lineEnd = text.index(afterCharacter: lineEnd)
                }

                if newLineStart < lineEnd {
                    text[newLineStart..<lineEnd].blockKind = blockKind
                }

                // Return new selection at line start
                return AttributedTextSelection(insertion: newLineStart)
            }
        }

        // Check for ordered list pattern (1. , 2. , etc.)
        if let match = lineText.wholeMatch(of: /^(\d+)\.\s$/) {
            text.removeSubrange(lineRange)

            let newLineStart = lineStart
            var lineEnd = newLineStart
            while lineEnd < text.endIndex && text.characters[lineEnd] != "\n" {
                lineEnd = text.index(afterCharacter: lineEnd)
            }

            if newLineStart < lineEnd {
                text[newLineStart..<lineEnd].blockKind = .orderedList
            }

            return AttributedTextSelection(insertion: newLineStart)
        }

        return nil
    }

    // MARK: - Inline Shortcuts

    private static func processInlineShortcuts(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index
    ) -> AttributedTextSelection? {

        // Check for inline patterns (e.g., **bold**)
        for (prefix, suffix, intent) in inlinePatterns {
            if let result = consumeInlinePattern(
                in: &text,
                at: cursorIndex,
                prefix: prefix,
                suffix: suffix,
                apply: { range in
                    let current = text[range].inlinePresentationIntent ?? []
                    text[range].inlinePresentationIntent = current.union(intent)
                }
            ) {
                return result
            }
        }

        // Check for strikethrough
        if let result = consumeInlinePattern(
            in: &text,
            at: cursorIndex,
            prefix: strikethroughPattern.0,
            suffix: strikethroughPattern.1,
            apply: { range in
                text[range].strikethroughStyle = .single
            }
        ) {
            return result
        }

        return nil
    }

    private static func consumeInlinePattern(
        in text: inout AttributedString,
        at cursorIndex: AttributedString.Index,
        prefix: String,
        suffix: String,
        apply: (Range<AttributedString.Index>) -> Void
    ) -> AttributedTextSelection? {

        // Look backwards for the pattern: prefix + content + suffix
        // Cursor is right after the closing suffix

        let prefixCount = prefix.count
        let suffixCount = suffix.count

        // Need at least prefix + 1 char + suffix behind cursor
        let minChars = prefixCount + 1 + suffixCount

        // Get text before cursor (up to reasonable length)
        var searchStart = cursorIndex
        var charCount = 0

        while searchStart > text.startIndex && charCount < 100 {
            searchStart = text.index(beforeCharacter: searchStart)
            charCount += 1
        }

        let searchText = String(text[searchStart..<cursorIndex].characters)

        // Check if ends with suffix
        guard searchText.hasSuffix(suffix) else { return nil }

        // Find the opening prefix
        let withoutSuffix = String(searchText.dropLast(suffixCount))
        guard let prefixRange = withoutSuffix.range(of: prefix, options: .backwards) else {
            return nil
        }

        let contentStart = withoutSuffix.index(after: prefixRange.upperBound)
        let content = String(withoutSuffix[contentStart...])

        // Content must not be empty and must not contain the prefix/suffix
        guard !content.isEmpty else { return nil }

        // Calculate the range in attributed string
        let prefixStartOffset = withoutSuffix.distance(from: withoutSuffix.startIndex, to: prefixRange.lowerBound)
        let prefixStart = text.index(searchStart, offsetByCharacters: prefixStartOffset)
        let contentStartAttr = text.index(prefixStart, offsetByCharacters: prefixCount)
        let contentEndAttr = text.index(cursorIndex, offsetByCharacters: -suffixCount)

        // Apply formatting to content
        apply(contentStartAttr..<contentEndAttr)

        // Remove prefix and suffix
        text.removeSubrange(contentEndAttr..<cursorIndex) // Remove suffix first
        text.removeSubrange(prefixStart..<contentStartAttr) // Remove prefix

        // Calculate new cursor position
        let newCursorIndex = text.index(prefixStart, offsetByCharacters: content.count)

        return AttributedTextSelection(insertion: newCursorIndex)
    }
}
```

### Phase 7: Integration with Existing Infrastructure

**Goal:** Connect the new editor to the existing NotesStore and NotesEditorViewModel.

#### 7.1 Update NotesEditorViewModel+Native.swift

```swift
// ios/sideBar/sideBar/ViewModels/NotesEditorViewModel+Native.swift

import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension NotesEditorViewModel {

    /// Create a NativeMarkdownEditorViewModel configured for this note
    func makeNativeEditorViewModel() -> NativeMarkdownEditorViewModel {
        let vm = NativeMarkdownEditorViewModel()
        vm.loadMarkdown(content)
        vm.isReadOnly = isReadOnly
        return vm
    }

    /// Sync changes from native editor back to this view model
    func syncFromNativeEditor(_ nativeVM: NativeMarkdownEditorViewModel) {
        let newMarkdown = nativeVM.currentMarkdown()
        if newMarkdown != content {
            content = newMarkdown
            // This triggers autosave via existing infrastructure
        }
    }
}
```

---

## Implementation Order

### Step-by-Step Execution Plan

| Phase | Description | Files to Create/Modify | Dependencies |
|-------|-------------|----------------------|--------------|
| 1.1 | Create custom attribute scope | `MarkdownEditorAttributes.swift` | None |
| 1.2 | Create formatting definition | `MarkdownFormattingDefinition.swift` | Phase 1.1 |
| 2.1 | Add swift-markdown package | `Package.swift` or Xcode | None |
| 2.2 | Create markdown importer | `MarkdownImporter.swift` | Phases 1.1, 2.1 |
| 3.1 | Create markdown exporter | `MarkdownExporter.swift` | Phase 1.1 |
| 4.1 | Create editor view model | `NativeMarkdownEditorViewModel.swift` | Phases 2.2, 3.1 |
| 5.1 | Create editor view | `NativeMarkdownEditorView.swift` | Phase 4.1 |
| 6.1 | Add shortcut processor | `MarkdownShortcutProcessor.swift` | Phase 1.1 |
| 7.1 | Integrate with existing VMs | `NotesEditorViewModel+Native.swift` | All above |

### Incremental Testing Approach

After each phase, create unit tests:

1. **After Phase 1:** Test that custom attributes can be set and read
2. **After Phase 2:** Test markdown → attributed string for each block type
3. **After Phase 3:** Test attributed string → markdown round-trip
4. **After Phase 4:** Test formatting commands modify attributed string correctly
5. **After Phase 5:** UI test that editor displays and accepts input
6. **After Phase 6:** Test that typing `**bold**` produces bold text
7. **After Phase 7:** Integration test with NotesStore

---

## File Structure

```
ios/sideBar/sideBar/
├── Utilities/
│   └── Markdown/
│       ├── MarkdownEditorAttributes.swift    # Phase 1.1
│       ├── MarkdownFormattingDefinition.swift # Phase 1.2
│       ├── MarkdownImporter.swift            # Phase 2.2
│       ├── MarkdownExporter.swift            # Phase 3.1
│       └── MarkdownShortcutProcessor.swift   # Phase 6.1
├── ViewModels/
│   ├── NativeMarkdownEditorViewModel.swift   # Phase 4.1
│   └── NotesEditorViewModel+Native.swift     # Phase 7.1
└── Views/
    └── Notes/
        └── NativeMarkdownEditorView.swift    # Phase 5.1
```

---

## Testing Strategy

### Unit Tests

```swift
// MarkdownImporterTests.swift
func testHeadingImport() {
    let importer = MarkdownImporter()
    let result = importer.attributedString(from: "# Hello")

    XCTAssertEqual(result.runs.first?.blockKind, .heading1)
}

func testBoldImport() {
    let importer = MarkdownImporter()
    let result = importer.attributedString(from: "**bold**")

    XCTAssertTrue(result.runs.first?.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
}
```

```swift
// MarkdownExporterTests.swift
func testHeadingExport() {
    var text = AttributedString("Hello")
    text.blockKind = .heading1

    let exporter = MarkdownExporter()
    let markdown = exporter.markdown(from: text)

    XCTAssertEqual(markdown, "# Hello")
}
```

```swift
// RoundTripTests.swift
func testRoundTrip() {
    let original = """
    # Heading

    This is **bold** and *italic*.

    - Item 1
    - Item 2

    > Quote
    """

    let importer = MarkdownImporter()
    let exporter = MarkdownExporter()

    let attributed = importer.attributedString(from: original)
    let exported = exporter.markdown(from: attributed)

    // Re-import and compare
    let reimported = importer.attributedString(from: exported)
    XCTAssertEqual(String(attributed.characters), String(reimported.characters))
}
```

### Integration Tests

Test the full flow:
1. Load a note from NotesStore
2. Edit in NativeMarkdownEditorView
3. Save changes back
4. Verify server receives correct markdown

---

## Migration Path

### Gradual Rollout

1. **Feature Flag:** Add `useNativeMarkdownEditor` flag in settings
2. **A/B Testing:** Enable for subset of users
3. **Fallback:** Use `SideBarMarkdown` as read-only fallback
4. **Full Migration:** Keep `SideBarMarkdown` for read-only contexts once native is stable

### Coexistence Period

During migration, both editors can coexist:

```swift
@ViewBuilder
var noteEditor: some View {
    if #available(iOS 26.0, macOS 26.0, *), settings.useNativeMarkdownEditor {
        NativeMarkdownEditorView(viewModel: nativeVM, onSave: save)
    } else {
        SideBarMarkdownContainer(text: content)
    }
}
```

---

## Known Limitations

1. **iOS 26+ Only:** Native editor requires iOS 26/macOS 26
2. **Tables:** Complex table editing may require custom handling
3. **Images:** Image embedding requires separate implementation
4. **Syntax Highlighting:** Code block syntax highlighting needs additional work

---

## Verification Checklist

After implementation, verify:

- [ ] Can create new note and type formatted text
- [ ] Bold, italic, strikethrough, code work via toolbar
- [ ] Heading levels 1-6 apply correctly
- [ ] Bullet and ordered lists work with nesting
- [ ] Task lists toggle between checked/unchecked
- [ ] Blockquotes display with indent
- [ ] Links are clickable and editable
- [ ] Typing `**bold**` converts to bold text
- [ ] Typing `# ` at line start creates heading
- [ ] Save persists to server as valid markdown
- [ ] Reload shows same formatting
- [ ] Round-trip: edit → save → reload preserves all formatting

---

## References

- [WWDC25 Session 280: Building Rich SwiftUI Text Experiences](https://developer.apple.com/videos/play/wwdc2025/280)
- [Apple Sample Code: RecipeEditor](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui)
- [swift-markdown Package](https://github.com/apple/swift-markdown)
- [AttributedString Documentation](https://developer.apple.com/documentation/foundation/attributedstring)
