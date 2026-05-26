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

}

#endif
