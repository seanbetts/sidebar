@preconcurrency import Foundation
import Combine
import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@MainActor
@available(iOS 26.0, macOS 26.0, *)
/// View model for editing and styling native markdown content.
public final class NativeMarkdownEditorViewModel: ObservableObject {
    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false {
        didSet {
            guard isReadOnly != oldValue else { return }
            updatePrefixVisibility()
        }
    }
    @Published public internal(set) var hasUnsavedChanges: Bool = false
    @Published public internal(set) var autosaveToken: Int = 0
    public var autosaveDelay: TimeInterval = 1.5

#if os(iOS)
    typealias PlatformFont = UIFont
    typealias PlatformFontWeight = UIFont.Weight
    typealias PlatformColor = UIColor
#elseif os(macOS)
    typealias PlatformFont = NSFont
    typealias PlatformFontWeight = NSFont.Weight
    typealias PlatformColor = NSColor
#endif

    let importer = MarkdownImporter()
    let exporter = MarkdownExporter()
    var baseFontSize: CGFloat = MarkdownTypography.defaultBodyFontSize
    var inlineCodeFontSize: CGFloat {
        MarkdownTypography.inlineCodeFontSize(baseFontSize: baseFontSize)
    }
    var bodyFont: Font {
        Font.system(size: baseFontSize)
    }
    var inlineCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    var blockCodeFont: Font {
        Font.system(size: inlineCodeFontSize, weight: .regular, design: .monospaced)
    }
    let style = SideBarMarkdownStyle.default
    var frontmatter: String?
    var lastSavedContent: String = ""
    var autosaveTask: Task<Void, Never>?
    var isApplyingShortcut = false
    var isUpdatingPrefixVisibility = false
    var usesInjectedListMarkers = true
    var lastSelectionLineSpan: ClosedRange<Int>?
    static let headingRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s"#)
    static let bulletRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s"#)
    static let orderedRegex = try? NSRegularExpression(pattern: #"^\s*\d+\.\s"#)
    static let taskRegex = try? NSRegularExpression(pattern: #"^\s*[-+*]\s+\[[ xX]\]\s"#)
    static let quoteRegex = try? NSRegularExpression(pattern: #"^\s*>\s"#)

    public init() {}

    public func setBaseFontSize(_ size: CGFloat) {
        baseFontSize = max(12, size)
    }

    public func loadMarkdown(_ markdown: String) {
        let result = importer.attributedString(from: markdown, baseFontSize: baseFontSize)
        frontmatter = result.frontmatter
        attributedContent = result.attributedString
        selection = AttributedTextSelection()
        lastSavedContent = markdown
        hasUnsavedChanges = false
        updatePrefixVisibility()
    }

    public func currentMarkdown() -> String {
        var exportContent = attributedContent
        let selection = selectionSnapshot(in: exportContent)
        _ = removeInjectedListMarkers(in: &exportContent, selection: selection)
        let constrained = MarkdownFormattingDefinition().constrainedDocument(exportContent)
        return exporter.markdown(from: constrained, frontmatter: frontmatter)
    }

    public func markSaved(markdown: String) {
        lastSavedContent = markdown
        hasUnsavedChanges = false
    }

    public func isBoldActive() -> Bool {
        hasInlineIntent(.stronglyEmphasized)
    }

    public func setBold(_ enabled: Bool) {
        applyInlineIntent(.stronglyEmphasized, enabled: enabled)
    }

    public func isItalicActive() -> Bool {
        hasInlineIntent(.emphasized)
    }

    public func setItalic(_ enabled: Bool) {
        applyInlineIntent(.emphasized, enabled: enabled)
    }

    public func toggleInlineCode() {
        let enabled = !hasInlineIntent(.code)
        applyInlineIntent(.code, enabled: enabled)
    }

    public func applyLink(_ url: URL) {
        attributedContent.transformAttributes(in: &selection) { attrs in
            attrs.link = url
            setForegroundColor(.accentColor, in: &attrs)
            attrs.underlineStyle = .single
        }
    }

    public func applyHeading(level: Int) {
        setBlockKind(headingKind(for: level))
    }

    public func applyList(ordered: Bool) {
        setBlockKind(ordered ? .orderedList : .bulletList, listDepth: 1)
    }

    public func applyTask() {
        setBlockKind(.taskUnchecked, listDepth: 1)
    }

    public func applyQuote() {
        setBlockKind(.blockquote)
    }

    public func applyCodeBlock(language: String?) {
        _ = language
        setBlockKind(.codeBlock)
    }

    public func applyFormatting(_ formatting: MarkdownFormatting) {
        guard !isReadOnly else { return }
        AttributedNoteFormattingCommands.apply(formatting, on: self)
    }

    public func handleContentChange(previous: AttributedString) {
        if isUpdatingPrefixVisibility {
            isUpdatingPrefixVisibility = false
            return
        }

        guard !isReadOnly, !isApplyingShortcut else {
            return
        }

        let insertedCharacter = lastInsertedCharacter(previous: previous, current: attributedContent)
        var updated = attributedContent
        stripUnsupportedInlineStyles(in: &updated)

        let shortcutResult = MarkdownShortcutProcessor.processShortcuts(
            in: &updated,
            selection: selection,
            lastInsertedCharacter: insertedCharacter,
            baseFontSize: baseFontSize
        )

        if let shortcutResult {
            isApplyingShortcut = true
            attributedContent = updated
            selection = shortcutResult.selection
            isApplyingShortcut = false
        } else if updated != attributedContent {
            isApplyingShortcut = true
            attributedContent = updated
            isApplyingShortcut = false
        }

        // Mark dirty immediately so close/switch flows can prompt even before autosave fires.
        hasUnsavedChanges = true
        scheduleAutosave()
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
        updatePrefixVisibility()
    }

    public func handleSelectionChange() {
        guard !isReadOnly, !isUpdatingPrefixVisibility else { return }
        let selectionSpan = selectionLineSpan(in: attributedContent)
        guard selectionSpan != lastSelectionLineSpan else { return }
        lastSelectionLineSpan = selectionSpan
        updatePrefixVisibility()
    }

    struct TableRowInfo {
        let isHeader: Bool
        let rowIndex: Int?
        let alignments: [PresentationIntent.TableColumn.Alignment]?
    }

    func tableRowInfo(from intent: PresentationIntent?) -> TableRowInfo? {
        guard let intent else { return nil }
        var isHeader = false
        var rowIndex: Int?
        var foundRow = false

        for component in intent.components {
            switch component.kind {
            case .tableHeaderRow:
                isHeader = true
                rowIndex = 0
                foundRow = true
            case .tableRow(let index):
                rowIndex = index
                foundRow = true
            default:
                break
            }
        }

        guard foundRow else { return nil }
        return TableRowInfo(isHeader: isHeader, rowIndex: rowIndex, alignments: nil)
    }

    func tableRowBackground(from info: TableRowInfo?) -> Color? {
        guard let info else { return nil }
        if info.isHeader {
            return DesignTokens.Colors.muted
        }
        if let rowIndex = info.rowIndex, rowIndex % 2 == 1 {
            return DesignTokens.Colors.muted.opacity(0.4)
        }
        return nil
    }

    func hasInlineIntent(_ intent: InlinePresentationIntent) -> Bool {
        let attrs = selection.typingAttributes(in: attributedContent)
        let intents = attrs.inlinePresentationIntent ?? []
        return intents.contains(intent)
    }

    func applyInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>? = nil
    ) {
        if let range {
            applyInlineIntentToRange(intent, enabled: enabled, range: range)
            return
        }
        attributedContent.transformAttributes(in: &selection) { attrs in
            updateInlineIntent(intent, enabled: enabled, attrs: &attrs)
        }
    }

    func updateInlineIntent(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        attrs: inout AttributeContainer
    ) {
        var intents = attrs.inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attrs.inlinePresentationIntent = intents

        if intent == .code {
            let blockKind = attrs.blockKind
            if enabled {
                setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attrs)
                setForegroundColor(DesignTokens.Colors.textPrimary, in: &attrs)
                setBackgroundColor(style.codeBackground, in: &attrs)
            } else {
                setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
                setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
                setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
            }
        }
    }

    func applyInlineIntentToRange(
        _ intent: InlinePresentationIntent,
        enabled: Bool,
        range: Range<AttributedString.Index>
    ) {
        var intents = attributedContent[range].inlinePresentationIntent ?? []
        if enabled {
            intents.insert(intent)
        } else {
            intents.remove(intent)
        }
        attributedContent[range].inlinePresentationIntent = intents

        guard intent == .code else { return }

        if enabled {
            setFont(inlineCodeFont, platformFont: platformInlineCodeFont(), in: &attributedContent, range: range)
            setForegroundColor(DesignTokens.Colors.textPrimary, in: &attributedContent, range: range)
            setBackgroundColor(style.codeBackground, in: &attributedContent, range: range)
        } else {
            let blockKind = attributedContent.blockKind(in: range)
            setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
            setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    func applyBlockStyle(blockKind: BlockKind, range: Range<AttributedString.Index>) {
        let font = blockKind == .codeBlock ? blockCodeFont : baseFont(for: blockKind)
        let platformFont = blockKind == .codeBlock ? platformInlineCodeFont() : platformBaseFont(for: blockKind)
        setFont(font, platformFont: platformFont, in: &attributedContent, range: range)
        setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attributedContent, range: range)
        let listDepth = attributedContent[range].listDepth
        if let paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth) {
            attributedContent[range].paragraphStyle = paragraphStyle
        }
        if blockKind == .taskChecked {
            setStrikethrough(true, in: &attributedContent, range: range)
            setForegroundColor(DesignTokens.Colors.textSecondary, in: &attributedContent, range: range)
        } else if blockKind == .taskUnchecked {
            setStrikethrough(false, in: &attributedContent, range: range)
            setForegroundColor(baseForegroundColor(for: blockKind), in: &attributedContent, range: range)
        }
    }

    func applyPresentationIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) {
        if let headingLevel = headingLevel(for: blockKind) {
            applyHeadingIntent(level: headingLevel, range: range)
            return
        }
        if applyListIntent(blockKind: blockKind, listDepth: listDepth, range: range) {
            return
        }
        switch blockKind {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            return
        case .bulletList, .orderedList, .taskChecked, .taskUnchecked:
            return
        case .blockquote:
            let quoteIntent = PresentationIntent(.blockQuote, identity: 1)
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1,
                parent: quoteIntent
            )
        case .codeBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .codeBlock(languageHint: nil),
                identity: 1
            )
        case .horizontalRule:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .thematicBreak,
                identity: 1
            )
        case .paragraph, .blankLine, .imageCaption, .gallery, .htmlBlock:
            attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1
            )
        @unknown default:
            return
        }
    }

    func headingLevel(for blockKind: BlockKind) -> Int? {
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

    func applyHeadingIntent(level: Int, range: Range<AttributedString.Index>) {
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .header(level: level),
            identity: level
        )
    }

    func applyListIntent(
        blockKind: BlockKind,
        listDepth: Int?,
        range: Range<AttributedString.Index>
    ) -> Bool {
        guard blockKind == .bulletList
            || blockKind == .orderedList
            || blockKind == .taskChecked
            || blockKind == .taskUnchecked
        else { return false }
        let listKind: PresentationIntent.Kind = blockKind == .orderedList ? .orderedList : .unorderedList
        let listId = listDepth ?? 1
        let listIntent = PresentationIntent(listKind, identity: listId)
        let listItemIntent = PresentationIntent(
            .listItem(ordinal: 1),
            identity: listId * 1000 + 1,
            parent: listIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
            .paragraph,
            identity: 1,
            parent: listItemIntent
        )
        attributedContent[range][AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        return true
    }

    func listDelimiter(for blockKind: BlockKind) -> Character? {
        switch blockKind {
        case .bulletList:
            return "•"
        case .taskChecked:
            return "☑"
        case .taskUnchecked:
            return "☐"
        default:
            return nil
        }
    }

}

@available(iOS 26.0, macOS 26.0, *)
/// Formatting actions available for native markdown editing.
public enum MarkdownFormatting {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case heading(level: Int)
    case promoteHeading
    case demoteHeading
    case bulletList
    case orderedList
    case taskList
    case indentList
    case outdentList
    case blockquote
    case codeBlock
    case link(URL)
    case horizontalRule
}
