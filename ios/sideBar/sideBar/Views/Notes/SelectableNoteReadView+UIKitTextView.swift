import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadTextView: UITextView {
    private static let baseTextContainerInsets = UIEdgeInsets(
        top: NoteTextLayout.verticalPadding,
        left: NoteTextLayout.horizontalPadding,
        bottom: NoteTextLayout.verticalPadding,
        right: NoteTextLayout.horizontalPadding
    )

    var document = NotesSemanticDocument(version: NotesSemanticDocument.currentVersion, blocks: [])
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var onInitialViewportRestorationApplied: (() -> Void)?
    var presentationGeneration: UInt64 = 0
    var initialViewportOffset: CGPoint? {
        didSet {
            guard initialViewportOffset != oldValue else { return }
            guard let initialViewportOffset else { return }
            pendingInitialViewportOffset = initialViewportOffset
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget? {
        didSet {
            guard initialViewportAnchorTarget != oldValue else { return }
            guard let initialViewportAnchorTarget else { return }
            pendingInitialViewportAnchorTarget = initialViewportAnchorTarget
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var initialViewportAnchorY: CGFloat? {
        didSet {
            guard initialViewportAnchorY != oldValue else { return }
            guard let initialViewportAnchorY else { return }
            pendingInitialViewportAnchorY = initialViewportAnchorY
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            hasAppliedInitialViewportOffset = false
            lastAppliedInitialViewportOffset = nil
            lastRequestedInitialViewportOffset = nil
            setNeedsLayout()
        }
    }
    var maxReadableContentWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { setNeedsLayout() }
    }
    var lastReportedViewportOffset: CGPoint?
    var hasAppliedInitialViewportOffset = true
    var isAwaitingPostRestorationStability = false
    var isAwaitingPostRestorationQuietPeriod = false
    var additionalViewportBottomInset: CGFloat = 0
    var lastAppliedInitialViewportOffset: CGPoint?
    var lastRequestedInitialViewportOffset: CGPoint?
    var pendingInitialViewportOffset: CGPoint?
    var pendingInitialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    var pendingInitialViewportAnchorY: CGFloat?
    var pendingInitialViewportStabilitySignature: InitialViewportStabilitySignature?
    var pendingPostRestorationStabilitySignature: PostRestorationStabilitySignature?
    var cachedCodeBlockBackgroundRects: [CGRect] = []
    var isCodeBlockBackgroundLayoutDirty = true
    var lastCodeBlockBackgroundLayoutBoundsWidth: CGFloat = 0
    var lastCodeBlockBackgroundLayoutInset: UIEdgeInsets = .zero

    override var contentOffset: CGPoint {
        didSet {
            reportViewportOffsetIfNeeded()
            setNeedsDisplay()
        }
    }

    override var contentSize: CGSize {
        didSet {
            guard contentSize != oldValue else { return }
            rearmInitialViewportAnchorRestorationIfNeeded()
            pendingInitialViewportStabilitySignature = nil
            if isAwaitingPostRestorationStability {
                pendingPostRestorationStabilitySignature = nil
                isAwaitingPostRestorationQuietPeriod = false
            }
            applyInitialViewportOffsetIfNeeded()
            reportViewportOffsetIfNeeded()
        }
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        super.setContentOffset(contentOffset, animated: animated)
        reportViewportOffsetIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTextContainerInsets()
        updateViewportInsets()
        updateCodeBlockBackgroundLayoutState()
        rearmInitialViewportAnchorRestorationIfNeeded()
        applyInitialViewportOffsetIfNeeded()
        reportViewportOffsetIfNeeded()
    }

    override func draw(_ rect: CGRect) {
        drawCodeBlockBackgrounds(in: rect)
        drawBlockquoteRules(in: rect)
        super.draw(rect)
    }

    private func updateTextContainerInsets() {
        let extraHorizontalInset = max((bounds.width - maxReadableContentWidth) / 2, 0)
        let resolvedInsets = UIEdgeInsets(
            top: Self.baseTextContainerInsets.top,
            left: Self.baseTextContainerInsets.left + extraHorizontalInset,
            bottom: Self.baseTextContainerInsets.bottom,
            right: Self.baseTextContainerInsets.right + extraHorizontalInset
        )
        guard textContainerInset != resolvedInsets else { return }
        textContainerInset = resolvedInsets
    }

    func linkAttribute(at point: CGPoint) -> Any? {
        guard attributedText.length > 0 else { return nil }
        guard let position = closestPosition(to: point) else { return nil }
        let characterIndex = min(
            max(offset(from: beginningOfDocument, to: position), 0),
            attributedText.length
        )
        guard characterIndex < attributedText.length,
              let characterStart = self.position(from: beginningOfDocument, offset: characterIndex),
              let characterEnd = self.position(from: characterStart, offset: 1),
              let characterRange = textRange(from: characterStart, to: characterEnd) else {
            return nil
        }
        let characterRect = firstRect(for: characterRange)
        guard characterRect.isNull == false,
              characterRect.insetBy(dx: -1, dy: -1).contains(point) else {
            return nil
        }
        return attributedText.attribute(.link, at: characterIndex, effectiveRange: nil)
    }

    func activationTarget(at point: CGPoint) -> SelectableNoteReadView.ReadActivationTarget? {
        guard linkAttribute(at: point) == nil,
              let readCharacterOffset = SelectableNoteReadView.characterOffsetForEditingActivation(in: self, at: point) else { return nil }
        return .characterOffset(
            SelectableNoteReadView.editingActivationCharacterOffset(
                in: document,
                readCharacterOffset: readCharacterOffset
            )
        )
    }

    func checklistToggleTarget(at point: CGPoint) -> SelectableNoteReadView.ChecklistToggleTarget? {
        guard linkAttribute(at: point) == nil else { return nil }

        for target in SelectableNoteReadView.checklistToggleTargets(in: document) {
            guard let checkboxRect = checkboxRect(for: target.checkboxRange) else { continue }
            if checkboxHitRect(for: checkboxRect).contains(point) {
                return target
            }
        }

        return nil
    }

    func activationViewportAnchorY(
        at point: CGPoint,
        target: SelectableNoteReadView.ReadActivationTarget
    ) -> CGFloat? {
        SelectableNoteReadView.viewportAnchorYForEditingActivation(
            in: self,
            target: target,
            fallbackPoint: point
        )
    }

    private func checkboxRect(for characterRange: NSRange) -> CGRect? {
        var combinedRect: CGRect?
        for characterIndex in characterRange.location..<(characterRange.location + characterRange.length) {
            guard let start = position(from: beginningOfDocument, offset: characterIndex) else {
                return nil
            }
            let characterRect = resolvedCharacterRect(
                at: start,
                nextPosition: position(from: start, offset: 1)
            )
            guard characterRect.isNull == false, characterRect.isEmpty == false else { return nil }
            combinedRect = combinedRect?.union(characterRect) ?? characterRect
        }
        return combinedRect
    }

    private func resolvedCharacterRect(
        at start: UITextPosition,
        nextPosition: UITextPosition?
    ) -> CGRect {
        if let nextPosition,
           let textRange = textRange(from: start, to: nextPosition) {
            let firstRect = firstRect(for: textRange)
            if firstRect.isNull == false, firstRect.isEmpty == false {
                return firstRect
            }
        }
        return caretRect(for: start)
    }

    private func checkboxHitRect(for checkboxRect: CGRect) -> CGRect {
        checkboxRect.insetBy(dx: -8, dy: -8)
    }
}

#endif
