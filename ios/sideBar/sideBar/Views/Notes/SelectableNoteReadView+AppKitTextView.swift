import SwiftUI
import sideBarShared
#if os(macOS)
import AppKit

@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadTextView: NSTextView {
    private static let baseTextContainerInset = NSSize(
        width: NoteTextLayout.horizontalPadding,
        height: NoteTextLayout.verticalPadding
    )

    var document = NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: [])
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var onInitialViewportRestorationApplied: (() -> Void)?
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet {
            updateTextContainerInset()
            needsLayout = true
        }
    }
    var presentationGeneration: UInt64 = 0 {
        didSet {
            guard presentationGeneration != oldValue else { return }
            rearmInitialPresentationReporting()
        }
    }
    private var didDragSelectionGesture = false
    private var lastActivationTimestamp: TimeInterval = 0
    private var lastReportedViewportOffset: CGPoint?
    private var didReportInitialPresentationReady = false
    private var isAwaitingInitialPresentationStability = false
    private var isAwaitingInitialPresentationQuietPeriod = false
    private var pendingInitialPresentationStabilitySignature: InitialPresentationStabilitySignature?

    private struct InitialPresentationStabilitySignature: Equatable {
        let boundsSize: CGSize
        let visibleRect: CGRect
        let textContainerInset: CGSize
        let textContainerSize: CGSize
        let usedRectSize: CGSize
        let viewportOffset: CGPoint
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportViewportOffsetIfNeeded()
        scheduleInitialViewportRestorationAppliedIfNeeded()
    }

    override func layout() {
        super.layout()
        updateTextContainerInset()
        reportViewportOffsetIfNeeded()
        scheduleInitialViewportRestorationAppliedIfNeeded()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBlockBackgrounds(in: dirtyRect)
        drawBlockquoteRules(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override func mouseDown(with event: NSEvent) {
        didDragSelectionGesture = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        didDragSelectionGesture = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let point = localPoint(for: event)
        super.mouseUp(with: event)
        guard event.clickCount == 1, didDragSelectionGesture == false else { return }
        activateEditingIfNeeded(at: point)
    }

    func installActivationClickRecognizerIfNeeded() {
        let hasRecognizer = gestureRecognizers.contains { recognizer in
            guard let clickRecognizer = recognizer as? NSClickGestureRecognizer else {
                return false
            }
            return clickRecognizer.numberOfClicksRequired == 1
        }
        guard hasRecognizer == false else { return }

        let clickRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleActivationClickGesture(_:))
        )
        clickRecognizer.numberOfClicksRequired = 1
        addGestureRecognizer(clickRecognizer)
    }

    @objc
    private func handleActivationClickGesture(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        activateEditingIfNeeded(at: recognizer.location(in: self))
    }

    private func activateEditingIfNeeded(at point: NSPoint) {
        if let checklistToggleTarget = checklistToggleTarget(at: point),
           let onToggleChecklistItem {
            lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                onToggleChecklistItem(checklistToggleTarget.blockIndex, checklistToggleTarget.itemIndex)
            }
            return
        }
        let target = activationTarget(at: point)
        let canTriggerActivationNow = canTriggerActivationNow
        guard let onActivateEditing, let target, canTriggerActivationNow else { return }
        lastActivationTimestamp = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async {
            onActivateEditing(target)
        }
    }

    private var canTriggerActivationNow: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return now - lastActivationTimestamp > 0.2
    }

    private func updateTextContainerInset() {
        guard let textContainer else { return }
        let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
        let resolvedInset = NSSize(
            width: Self.baseTextContainerInset.width + extraHorizontalInset,
            height: Self.baseTextContainerInset.height
        )
        let fallbackContainerWidth = max(
            maxReadableContentWidth - (Self.baseTextContainerInset.width * 2),
            0
        )
        let resolvedContainerWidth =
            bounds.width > 0
            ? max(bounds.width - (resolvedInset.width * 2), 0)
            : fallbackContainerWidth
        let resolvedContainerSize = NSSize(
            width: resolvedContainerWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        let needsInsetUpdate = textContainerInset != resolvedInset
        let needsContainerResize =
            textContainer.widthTracksTextView
            || abs(textContainer.containerSize.width - resolvedContainerSize.width) > 0.5
            || abs(textContainer.containerSize.height - resolvedContainerSize.height) > 0.5

        guard needsInsetUpdate || needsContainerResize else { return }
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.containerSize = resolvedContainerSize
        textContainerInset = resolvedInset
    }

    private func localPoint(for event: NSEvent) -> NSPoint {
        guard window != nil || event.windowNumber != 0 else {
            return event.locationInWindow
        }
        return convert(event.locationInWindow, from: nil)
    }

    private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        guard let textStorage,
              let layoutManager,
              let textContainer else { return }
        let backgroundRects = NoteTextCodeBlockBackgroundLayout.blockRects(
            in: textStorage,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textContainerInset: textContainerInset
        )
        guard backgroundRects.isEmpty == false else { return }

        NoteTextAppearance.codeBlockBackgroundColor.setFill()
        for backgroundRect in backgroundRects where backgroundRect.intersects(dirtyRect) {
            NSBezierPath(
                roundedRect: backgroundRect,
                xRadius: NoteTextAppearance.codeBlockCornerRadius,
                yRadius: NoteTextAppearance.codeBlockCornerRadius
                ).fill()
        }
    }

    private func reportViewportOffsetIfNeeded() {
        let offset = enclosingScrollView?.contentView.bounds.origin ?? .zero
        guard lastReportedViewportOffset != offset else { return }
        lastReportedViewportOffset = offset
        onViewportOffsetChange?(offset)
    }

    private func rearmInitialPresentationReporting() {
        didReportInitialPresentationReady = false
        isAwaitingInitialPresentationStability = false
        isAwaitingInitialPresentationQuietPeriod = false
        pendingInitialPresentationStabilitySignature = nil
        DispatchQueue.main.async { [weak self] in
            self?.scheduleInitialViewportRestorationAppliedIfNeeded()
        }
    }

    private func scheduleInitialViewportRestorationAppliedIfNeeded() {
        guard !didReportInitialPresentationReady,
              window != nil,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        guard let stabilitySignature = currentInitialPresentationStabilitySignature() else {
            return
        }
        if isAwaitingInitialPresentationStability == false {
            isAwaitingInitialPresentationStability = true
            pendingInitialPresentationStabilitySignature = stabilitySignature
            isAwaitingInitialPresentationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfNeeded()
            }
            return
        }
        if pendingInitialPresentationStabilitySignature != stabilitySignature {
            pendingInitialPresentationStabilitySignature = stabilitySignature
            isAwaitingInitialPresentationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfNeeded()
            }
            return
        }
        guard isAwaitingInitialPresentationQuietPeriod == false else { return }
        isAwaitingInitialPresentationQuietPeriod = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard self.didReportInitialPresentationReady == false,
                  self.isAwaitingInitialPresentationStability,
                  self.isAwaitingInitialPresentationQuietPeriod,
                  let currentSignature = self.currentInitialPresentationStabilitySignature(),
                  self.pendingInitialPresentationStabilitySignature == stabilitySignature,
                  currentSignature == stabilitySignature else {
                return
            }
            self.didReportInitialPresentationReady = true
            self.isAwaitingInitialPresentationStability = false
            self.isAwaitingInitialPresentationQuietPeriod = false
            self.pendingInitialPresentationStabilitySignature = nil
            self.reportViewportOffsetIfNeeded()
            DispatchQueue.main.async { [weak self] in
                self?.onInitialViewportRestorationApplied?()
            }
        }
    }

    private func currentInitialPresentationStabilitySignature() -> InitialPresentationStabilitySignature? {
        guard let textContainer,
              let layoutManager else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let visibleRect = enclosingScrollView?.contentView.documentVisibleRect ?? .zero
        let viewportOffset = enclosingScrollView?.contentView.bounds.origin ?? .zero
        let usedRect = layoutManager.usedRect(for: textContainer)
        return InitialPresentationStabilitySignature(
            boundsSize: bounds.size,
            visibleRect: visibleRect,
            textContainerInset: textContainerInset,
            textContainerSize: textContainer.containerSize,
            usedRectSize: usedRect.size,
            viewportOffset: viewportOffset
        )
    }

    private func drawBlockquoteRules(in dirtyRect: NSRect) {
        guard let textStorage,
              let layoutManager,
              let textContainer else { return }
        let ruleRects = NoteTextBlockquoteDecorationLayout.ruleRects(
            in: textStorage,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textContainerInset: textContainerInset
        )
        guard ruleRects.isEmpty == false else { return }

        NoteTextAppearance.blockquoteRuleColor.setFill()
        for ruleRect in ruleRects where ruleRect.intersects(dirtyRect) {
            NSBezierPath(roundedRect: ruleRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func linkAttribute(at point: NSPoint) -> Any? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphBounds.insetBy(dx: -1, dy: -1).contains(containerPoint) else { return nil }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    private func activationTarget(at point: NSPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let readCharacterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: readCharacterOffset
            )
        )
    }

    private func checklistToggleTarget(at point: NSPoint) -> SelectableNoteReadView.ChecklistToggleTarget? {
        guard linkAttribute(at: point) == nil else { return nil }

        for target in SelectableNoteReadView.checklistToggleTargets(in: document) {
            guard let checkboxRect = checkboxRect(for: target.checkboxRange) else { continue }
            if checkboxHitRect(for: checkboxRect).contains(point) {
                return target
            }
        }

        return nil
    }

    private func checkboxRect(for characterRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        textContainer.containerSize = NSSize(
            width: bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        return rect
    }

    private func checkboxHitRect(for checkboxRect: NSRect) -> NSRect {
        checkboxRect.insetBy(dx: -6, dy: -6)
    }
}
#endif
