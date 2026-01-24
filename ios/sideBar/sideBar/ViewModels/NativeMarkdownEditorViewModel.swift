import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
public final class NativeMarkdownEditorViewModel: ObservableObject {
    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false
    @Published public private(set) var hasUnsavedChanges: Bool = false

    private let importer = MarkdownImporter()
    private let exporter = MarkdownExporter()
    private var frontmatter: String?
    private var lastSavedContent: String = ""
    private var autosaveTask: Task<Void, Never>?
    private var isApplyingShortcut = false

    public init() {}

    public func loadMarkdown(_ markdown: String) {
        let result = importer.attributedString(from: markdown)
        frontmatter = result.frontmatter
        attributedContent = result.attributedString
        selection = AttributedTextSelection()
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    public func currentMarkdown() -> String {
        exporter.markdown(from: attributedContent, frontmatter: frontmatter)
    }

    public func markSaved(markdown: String) {
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    public func applyFormatting(_ formatting: MarkdownFormatting) {
        guard !isReadOnly else { return }

        switch formatting {
        case .bold:
            toggleInlineIntent(.stronglyEmphasized)
        case .italic:
            toggleInlineIntent(.emphasized)
        case .inlineCode:
            toggleInlineIntent(.code)
        case .strikethrough:
            toggleStrikethrough()
        case .heading(let level):
            setBlockKind(headingKind(for: level))
        case .bulletList:
            setBlockKind(.bulletList, listDepth: 1)
        case .orderedList:
            setBlockKind(.orderedList, listDepth: 1)
        case .taskList:
            setBlockKind(.taskUnchecked, listDepth: 1)
        case .blockquote:
            setBlockKind(.blockquote)
        case .codeBlock:
            setBlockKind(.codeBlock)
        case .link(let url):
            insertLink(url)
        case .horizontalRule:
            insertHorizontalRule()
        }
    }

    public func handleContentChange(previous: AttributedString) {
        guard !isReadOnly, !isApplyingShortcut else {
            return
        }

        let insertedCharacter = lastInsertedCharacter(previous: previous, current: attributedContent)
        var updated = attributedContent

        if let newSelection = MarkdownShortcutProcessor.processShortcuts(
            in: &updated,
            selection: selection,
            lastInsertedCharacter: insertedCharacter
        ) {
            isApplyingShortcut = true
            attributedContent = updated
            selection = newSelection
            isApplyingShortcut = false
        }

        scheduleAutosave()
    }

    private func toggleInlineIntent(_ intent: InlinePresentationIntent) {
        let ranges = selection.indices(in: attributedContent).ranges
        for range in ranges where !range.isEmpty {
            let current = attributedContent[range].inlinePresentationIntent ?? []
            if current.contains(intent) {
                attributedContent[range].inlinePresentationIntent = current.subtracting(intent)
            } else {
                attributedContent[range].inlinePresentationIntent = current.union(intent)
            }
        }
    }

    private func toggleStrikethrough() {
        let ranges = selection.indices(in: attributedContent).ranges
        for range in ranges where !range.isEmpty {
            if attributedContent[range].strikethroughStyle == nil {
                attributedContent[range].strikethroughStyle = .single
            } else {
                attributedContent[range].strikethroughStyle = nil
            }
        }
    }

    private func setBlockKind(_ blockKind: BlockKind, listDepth: Int? = nil) {
        let ranges = selection.indices(in: attributedContent).ranges
        for range in ranges {
            let paragraphRange = findParagraphRange(containing: range)
            attributedContent[paragraphRange].blockKind = blockKind
            if let listDepth {
                attributedContent[paragraphRange].listDepth = listDepth
            } else {
                attributedContent[paragraphRange].listDepth = nil
            }
        }
    }

    private func findParagraphRange(containing range: Range<AttributedString.Index>) -> Range<AttributedString.Index> {
        var start = range.lowerBound
        var end = range.upperBound

        while start > attributedContent.startIndex {
            let prev = attributedContent.index(beforeCharacter: start)
            if attributedContent.characters[prev] == "\n" {
                break
            }
            start = prev
        }

        while end < attributedContent.endIndex {
            if attributedContent.characters[end] == "\n" {
                break
            }
            end = attributedContent.index(afterCharacter: end)
        }

        return start..<end
    }

    private func insertLink(_ url: URL) {
        let ranges = selection.indices(in: attributedContent).ranges
        guard let range = ranges.first else { return }

        if range.isEmpty {
            let placeholder = AttributedString("link")
            var insert = placeholder
            insert.link = url
            attributedContent.insert(insert, at: range.lowerBound)
            selection = AttributedTextSelection(insertion: attributedContent.index(range.lowerBound, offsetByCharacters: placeholder.characters.count))
        } else {
            attributedContent[range].link = url
            attributedContent[range].foregroundColor = .accentColor
            attributedContent[range].underlineStyle = .single
        }
    }

    private func insertHorizontalRule() {
        var hr = AttributedString("---")
        hr.blockKind = .horizontalRule
        hr.foregroundColor = DesignTokens.Colors.border

        let insertIndex = selection.indices(in: attributedContent).ranges.first?.lowerBound ?? attributedContent.endIndex
        attributedContent.insert(hr, at: insertIndex)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self else { return }
            let current = self.currentMarkdown()
            self.hasUnsavedChanges = current != self.lastSavedContent
        }
    }

    private func lastInsertedCharacter(previous: AttributedString, current: AttributedString) -> Character? {
        let prev = String(previous.characters)
        let curr = String(current.characters)
        guard curr.count == prev.count + 1 else { return nil }

        var prevIndex = prev.startIndex
        var currIndex = curr.startIndex

        while prevIndex < prev.endIndex && currIndex < curr.endIndex {
            if prev[prevIndex] != curr[currIndex] {
                return curr[currIndex]
            }
            prevIndex = prev.index(after: prevIndex)
            currIndex = curr.index(after: currIndex)
        }

        if currIndex < curr.endIndex {
            return curr[currIndex]
        }

        return nil
    }

    private func headingKind(for level: Int) -> BlockKind {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
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
