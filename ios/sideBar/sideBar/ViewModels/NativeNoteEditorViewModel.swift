@preconcurrency import Foundation
import Combine
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
/// View model for editing and styling native note content.
public final class NativeNoteEditorViewModel: ObservableObject {
    @Published public var attributedContent: AttributedString = AttributedString()
    @Published public var selection: AttributedTextSelection = AttributedTextSelection()
    @Published public var isReadOnly: Bool = false
    @Published public internal(set) var hasUnsavedChanges: Bool = false
    @Published public internal(set) var autosaveToken: Int = 0
    public var autosaveDelay: TimeInterval = 1.5
    var minimumAutosaveDelay: TimeInterval = 0.3

    var baseFontSize: CGFloat = NoteTextTypography.defaultBodyFontSize
    var bodyFont: Font {
        Font.system(size: baseFontSize)
    }
    var lastSavedContent: String = ""
    var lastSavedCanonicalContent: String = ""
    var autosaveTask: Task<Void, Never>?
    var lastHandledContentSourceGeneration: Int = 0
    var lastHandledSelectionSourceGeneration: Int = 0
    var lastSelectionLineSpan: ClosedRange<Int>?

    public init() {}

    deinit {
        autosaveTask?.cancel()
    }

    public func setBaseFontSize(_ size: CGFloat) {
        let updatedSize = max(12, size)
        guard abs(baseFontSize - updatedSize) > 0.1 else { return }
        baseFontSize = updatedSize
        normalizeDocumentStylingForDisplay()
    }

    public func currentPlainText() -> String {
        NotePlainTextProjection.plainText(from: attributedContent)
    }

    func defaultTypingAttributes() -> AttributeContainer {
        var attrs = AttributeContainer()
        applyInlineFormattingState(.plain, to: &attrs)
        attrs.paragraphStyle = NoteTextParagraphMetrics.bodyParagraphStyle(baseFontSize: baseFontSize)
        return attrs
    }

    public func isBoldActive() -> Bool {
        isFormattingActive(.bold)
    }

    public func setBold(_ enabled: Bool) {
        setFormatting(.bold, enabled: enabled)
    }

    public func isItalicActive() -> Bool {
        isFormattingActive(.italic)
    }

    public func setItalic(_ enabled: Bool) {
        setFormatting(.italic, enabled: enabled)
    }

    public func applyFormatting(_ formatting: NoteFormatting) {
        guard !isReadOnly else { return }
        let previousContent = attributedContent
        let previousSelection = selection
        toggleFormatting(formatting)
        guard attributedContent != previousContent || selection != previousSelection else { return }

        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        scheduleAutosave()
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
    }

    public func activeTextStyle() -> NoteTextStyle {
        activeTextStyleAtSelectionStart()
    }

    public func applyTextStyle(_ style: NoteTextStyle) {
        guard !isReadOnly else { return }
        let previousContent = attributedContent
        let previousSelection = selection
        setTextStyle(style)
        guard attributedContent != previousContent || selection != previousSelection else { return }

        if !hasUnsavedChanges {
            hasUnsavedChanges = true
        }
        scheduleAutosave()
        lastSelectionLineSpan = selectionLineSpan(in: attributedContent)
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

    func applySelectionTarget(_ target: NotesEditorViewModel.PendingEditSelectionTarget) {
        switch target {
        case .start:
            setInsertionPoint(characterOffset: 0)
        case .characterOffset(let offset):
            setInsertionPoint(characterOffset: offset)
        }
    }

}
