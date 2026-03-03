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
/// View model for editing and styling native note content.
public final class NativeNoteEditorViewModel: ObservableObject {
    static let noteStyle = NoteTextStyle.default

    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false
    @Published public internal(set) var hasUnsavedChanges: Bool = false
    @Published public internal(set) var autosaveToken: Int = 0
    @Published public private(set) var styleSyncGeneration: Int = 0
    @Published var enabledFormattingCapabilities: Set<NoteFormattingCapability> = []
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

    var baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    var inlineCodeFontSize: CGFloat {
        NoteTextTypography.inlineCodeFontSize(baseFontSize: baseFontSize)
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
    var lastSavedContent: String = ""
    var lastSavedCanonicalContent: String = ""
    var autosaveTask: Task<Void, Never>?
    var isUpdatingPrefixVisibility = false
    var usesInjectedListMarkers = false
    var prefixRefreshTask: Task<Void, Never>?
    var pendingPrefixRefreshScope: PrefixRefreshScope?
    var lastHandledContentSourceGeneration: Int = 0
    var lastHandledSelectionSourceGeneration: Int = 0
    var lastSelectionLineSpan: ClosedRange<Int>?
    var plainTextRuntimeModeEnabled: Bool = false

    public init() {}

    public func setBaseFontSize(_ size: CGFloat) {
        let updatedSize = max(12, size)
        guard abs(baseFontSize - updatedSize) > 0.1 else { return }
        baseFontSize = updatedSize
        normalizeDocumentStylingForDisplay()
        styleSyncGeneration &+= 1
    }

    public func currentPlainText() -> String {
        String(attributedContent.characters)
    }

    func defaultTypingAttributes(
        blockKind: BlockKind = .paragraph,
        listDepth: Int? = nil
    ) -> AttributeContainer {
        if plainTextRuntimeModeEnabled {
            var plainAttrs = AttributeContainer()
            plainAttrs.blockKind = .paragraph
            plainAttrs.listDepth = nil
            plainAttrs.codeLanguage = nil
            setFont(baseFont(for: .paragraph), platformFont: platformBaseFont(for: .paragraph), in: &plainAttrs)
            setForegroundColor(baseForegroundColor(for: .paragraph), in: &plainAttrs)
            setBackgroundColor(nil, in: &plainAttrs)
            plainAttrs.paragraphStyle = plainTextRuntimeParagraphStyle()
            plainAttrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = PresentationIntent(
                .paragraph,
                identity: 1
            )
            plainAttrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = nil
            plainAttrs.strikethroughStyle = nil
            return plainAttrs
        }

        var attrs = AttributeContainer()
        attrs.blockKind = blockKind
        attrs.listDepth = listDepth
        attrs.codeLanguage = nil
        setFont(baseFont(for: blockKind), platformFont: platformBaseFont(for: blockKind), in: &attrs)
        setForegroundColor(baseForegroundColor(for: blockKind), in: &attrs)
        setBackgroundColor(baseBackgroundColor(for: blockKind), in: &attrs)
        attrs.paragraphStyle = paragraphStyle(for: blockKind, listDepth: listDepth)
        attrs[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self] = typingPresentationIntent(
            blockKind: blockKind,
            listDepth: listDepth
        )
        attrs[AttributeScopes.FoundationAttributes.ListItemDelimiterAttribute.self] = listDelimiter(for: blockKind)
        attrs.strikethroughStyle = blockKind == .taskChecked ? .single : nil
        return attrs
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
        transformSelectionAttributes { attrs in
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

    public func applyFormatting(_ formatting: NoteFormatting) {
        guard !isReadOnly else { return }
        if plainTextRuntimeModeEnabled,
           let capability = formatting.runtimeCapability,
           !enabledFormattingCapabilities.contains(capability) {
            return
        }
        if plainTextRuntimeModeEnabled,
           formatting.runtimeCapability == nil {
            return
        }
        let previousContent = attributedContent
        let previousSelection = selection
        AttributedNoteFormattingCommands.apply(formatting, on: self)
        guard attributedContent != previousContent || selection != previousSelection else { return }

        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        let currentSelectionSpan = selectionLineSpan(in: attributedContent)
        requestPrefixRefresh(scope: .lineSpan(unionLineSpan(lastSelectionLineSpan, currentSelectionSpan)))
        scheduleAutosave()
        lastSelectionLineSpan = currentSelectionSpan
    }

    public func handleContentChange(previous: AttributedString) {
        handleContentChange(previous: previous, sourceGeneration: nil)
    }

    public func handleContentChange(previous: AttributedString, sourceGeneration: Int?) {
        guard !isReadOnly else { return }
        if let sourceGeneration {
            guard sourceGeneration > lastHandledContentSourceGeneration else { return }
            lastHandledContentSourceGeneration = sourceGeneration
        }
        guard attributedContent != previous else { return }

        if plainTextRuntimeModeEnabled {
            normalizeCurrentContentForPlainTextRuntime()
        } else {
            var normalizedContent = attributedContent
            stripUnsupportedInlineStyles(in: &normalizedContent)
            if applyDetectedLinks(in: &normalizedContent) || normalizedContent != attributedContent {
                if attributedContent != normalizedContent {
                    attributedContent = normalizedContent
                }
            }
        }

        // Mark dirty immediately so close/switch flows can prompt even before autosave fires.
        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        scheduleAutosave()
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    public func handleSelectionChange() {
        handleSelectionChange(sourceGeneration: nil)
    }

    public func handleSelectionChange(sourceGeneration: Int?) {
        guard !isReadOnly else { return }
        if let sourceGeneration {
            guard sourceGeneration > lastHandledSelectionSourceGeneration else { return }
            lastHandledSelectionSourceGeneration = sourceGeneration
        }
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

}
