import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadTextView {
    func updateViewportInsets() {
        guard abs(contentInset.bottom - additionalViewportBottomInset) > 0.5 else { return }
        contentInset.bottom = additionalViewportBottomInset
        var indicatorInsets = verticalScrollIndicatorInsets
        indicatorInsets.bottom = additionalViewportBottomInset
        verticalScrollIndicatorInsets = indicatorInsets
    }

    func invalidateCodeBlockBackgroundLayout() {
        isCodeBlockBackgroundLayoutDirty = true
        cachedCodeBlockBackgroundRects = []
        setNeedsDisplay()
    }

    func updateCodeBlockBackgroundLayoutState() {
        let widthChanged = abs(lastCodeBlockBackgroundLayoutBoundsWidth - bounds.width) > 0.5
        let insetChanged = lastCodeBlockBackgroundLayoutInset != textContainerInset
        guard widthChanged || insetChanged else { return }
        lastCodeBlockBackgroundLayoutBoundsWidth = bounds.width
        lastCodeBlockBackgroundLayoutInset = textContainerInset
        invalidateCodeBlockBackgroundLayout()
    }

    func drawCodeBlockBackgrounds(in rect: CGRect) {
        guard attributedText.length > 0 else { return }
        let backgroundRects = resolvedCodeBlockBackgroundRects()
        guard backgroundRects.isEmpty == false else { return }

        NoteTextAppearance.codeBlockBackgroundColor.setFill()
        for backgroundRect in backgroundRects where backgroundRect.intersects(rect) {
            UIBezierPath(
                roundedRect: backgroundRect,
                cornerRadius: NoteTextAppearance.codeBlockCornerRadius
                ).fill()
        }
    }

    func drawBlockquoteRules(in rect: CGRect) {
        guard attributedText.length > 0 else { return }
        let ruleRects = NoteTextBlockquoteDecorationLayout.detachedRuleRects(
            in: attributedText,
            containerWidth: bounds.width,
            textContainerInset: CGSize(
                width: textContainerInset.left,
                height: textContainerInset.top
            )
        )
        guard ruleRects.isEmpty == false else { return }

        NoteTextAppearance.blockquoteRuleColor.setFill()
        for ruleRect in ruleRects where ruleRect.intersects(rect) {
            UIBezierPath(roundedRect: ruleRect, cornerRadius: 1.5).fill()
        }
    }

    private func resolvedCodeBlockBackgroundRects() -> [CGRect] {
        guard isCodeBlockBackgroundLayoutDirty else { return cachedCodeBlockBackgroundRects }
        cachedCodeBlockBackgroundRects = NoteTextCodeBlockBackgroundLayout.detachedBlockRects(
            in: attributedText,
            containerWidth: bounds.width,
            textContainerInset: CGSize(
                width: textContainerInset.left,
                height: textContainerInset.top
            )
        )
        isCodeBlockBackgroundLayoutDirty = false
        return cachedCodeBlockBackgroundRects
    }

    func reportViewportOffsetIfNeeded(force: Bool = false) {
        guard force || hasPendingInitialViewportRestoration == false else { return }
        guard force || lastReportedViewportOffset != contentOffset else { return }
        lastReportedViewportOffset = contentOffset
        onViewportOffsetChange?(contentOffset)
    }

    func rearmInitialViewportAnchorRestorationIfNeeded() {
        guard hasPendingInitialViewportRestoration == false,
              hasAppliedInitialViewportOffset,
              let initialViewportAnchorTarget,
              let initialViewportAnchorY,
              let lastAppliedInitialViewportOffset,
              abs(contentOffset.x - lastAppliedInitialViewportOffset.x) <= 0.5,
              abs(contentOffset.y - lastAppliedInitialViewportOffset.y) <= 0.5,
              let requestedOffset = SelectableNoteReadView.contentOffset(
                forViewportAnchorY: initialViewportAnchorY,
                in: self,
                target: initialViewportAnchorTarget
              ) else {
            return
        }

        let clampedOffset = clampedContentOffset(for: requestedOffset)
        guard abs(clampedOffset.x - contentOffset.x) > 0.5
                || abs(clampedOffset.y - contentOffset.y) > 0.5 else {
            return
        }

        pendingInitialViewportOffset = initialViewportOffset
        pendingInitialViewportAnchorTarget = initialViewportAnchorTarget
        pendingInitialViewportAnchorY = initialViewportAnchorY
        pendingInitialViewportStabilitySignature = nil
        pendingPostRestorationStabilitySignature = nil
        isAwaitingPostRestorationStability = false
        isAwaitingPostRestorationQuietPeriod = false
        hasAppliedInitialViewportOffset = false
        lastRequestedInitialViewportOffset = nil
    }

    func applyInitialViewportOffsetIfNeeded() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let restoration = resolvedInitialViewportRestoration()
        guard let restoration else {
            if hasPendingInitialViewportRestoration { return }
            hasAppliedInitialViewportOffset = true
            return
        }
        let additionalBottomInsetNeeded = max(
            restoration.requestedOffset.y - clampedContentOffset(for: restoration.requestedOffset).y,
            0
        )
        if abs(additionalViewportBottomInset - additionalBottomInsetNeeded) > 0.5 {
            additionalViewportBottomInset = additionalBottomInsetNeeded
            updateViewportInsets()
            DispatchQueue.main.async { [weak self] in
                self?.applyInitialViewportOffsetIfNeeded()
            }
            return
        }
        let needsOffsetUpdate =
            abs(contentOffset.x - restoration.offset.x) > 0.5
                || abs(contentOffset.y - restoration.offset.y) > 0.5
        if needsOffsetUpdate {
            super.setContentOffset(restoration.offset, animated: false)
            pendingInitialViewportStabilitySignature = nil
            pendingPostRestorationStabilitySignature = nil
            isAwaitingPostRestorationStability = false
            isAwaitingPostRestorationQuietPeriod = false
            lastAppliedInitialViewportOffset = restoration.offset
            lastRequestedInitialViewportOffset = restoration.requestedOffset
            hasAppliedInitialViewportOffset = false
            return
        }
        if lastAppliedInitialViewportOffset != restoration.offset {
            lastAppliedInitialViewportOffset = restoration.offset
        }
        if lastRequestedInitialViewportOffset != restoration.requestedOffset {
            lastRequestedInitialViewportOffset = restoration.requestedOffset
        }
        let stabilitySignature = InitialViewportStabilitySignature(
            offset: restoration.offset,
            contentSize: contentSize,
            boundsSize: bounds.size
        )
        if pendingInitialViewportStabilitySignature != stabilitySignature {
            pendingInitialViewportStabilitySignature = stabilitySignature
            if restoration.isClamped {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.applyInitialViewportOffsetIfNeeded()
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyInitialViewportOffsetIfNeeded()
                }
            }
            return
        }
        guard hasAppliedInitialViewportOffset == false else { return }
        pendingInitialViewportStabilitySignature = nil
        hasAppliedInitialViewportOffset = true
        lastRequestedInitialViewportOffset = nil
        pendingInitialViewportOffset = nil
        pendingInitialViewportAnchorTarget = nil
        pendingInitialViewportAnchorY = nil
        reportViewportOffsetIfNeeded(force: true)
        scheduleInitialViewportRestorationAppliedIfStable()
    }

    struct InitialViewportRestoration {
        let mode: String
        let offset: CGPoint
        let requestedOffset: CGPoint
        let viewportAnchorY: String

        var isClamped: Bool {
            abs(offset.x - requestedOffset.x) > 0.5 || abs(offset.y - requestedOffset.y) > 0.5
        }
    }

    struct InitialViewportStabilitySignature: Equatable {
        let offset: CGPoint
        let contentSize: CGSize
        let boundsSize: CGSize
    }

    struct PostRestorationStabilitySignature: Equatable {
        let offset: CGPoint
        let contentSize: CGSize
        let boundsSize: CGSize
    }

    var hasPendingInitialViewportRestoration: Bool {
        pendingInitialViewportOffset != nil
            || pendingInitialViewportAnchorTarget != nil
            || pendingInitialViewportAnchorY != nil
    }

    private func scheduleInitialViewportRestorationAppliedIfStable() {
        let stabilitySignature = PostRestorationStabilitySignature(
            offset: contentOffset,
            contentSize: contentSize,
            boundsSize: bounds.size
        )
        if isAwaitingPostRestorationStability == false {
            isAwaitingPostRestorationStability = true
            pendingPostRestorationStabilitySignature = stabilitySignature
            isAwaitingPostRestorationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfStable()
            }
            return
        }
        if pendingPostRestorationStabilitySignature != stabilitySignature {
            pendingPostRestorationStabilitySignature = stabilitySignature
            isAwaitingPostRestorationQuietPeriod = false
            DispatchQueue.main.async { [weak self] in
                self?.scheduleInitialViewportRestorationAppliedIfStable()
            }
            return
        }
        guard isAwaitingPostRestorationQuietPeriod == false else { return }
        isAwaitingPostRestorationQuietPeriod = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let currentSignature = PostRestorationStabilitySignature(
                offset: self.contentOffset,
                contentSize: self.contentSize,
                boundsSize: self.bounds.size
            )
            guard self.isAwaitingPostRestorationStability,
                  self.isAwaitingPostRestorationQuietPeriod,
                  self.pendingPostRestorationStabilitySignature == stabilitySignature,
                  currentSignature == stabilitySignature
            else {
                return
            }
            self.isAwaitingPostRestorationStability = false
            self.isAwaitingPostRestorationQuietPeriod = false
            self.pendingPostRestorationStabilitySignature = nil
            self.onInitialViewportRestorationApplied?()
        }
    }

    private func resolvedInitialViewportRestoration() -> InitialViewportRestoration? {
        if let pendingInitialViewportAnchorTarget,
           let pendingInitialViewportAnchorY,
           let requestedOffset = SelectableNoteReadView.contentOffset(
                forViewportAnchorY: pendingInitialViewportAnchorY,
                in: self,
                target: pendingInitialViewportAnchorTarget
           ) {
            return InitialViewportRestoration(
                mode: pendingInitialViewportOffset == nil ? "anchor" : "anchor-preferred",
                offset: clampedContentOffset(for: requestedOffset),
                requestedOffset: requestedOffset,
                viewportAnchorY: String(format: "%.2f", pendingInitialViewportAnchorY)
            )
        }
        if let pendingInitialViewportOffset {
            return InitialViewportRestoration(
                mode: pendingInitialViewportAnchorTarget == nil ? "offset" : "offset-fallback",
                offset: clampedContentOffset(for: pendingInitialViewportOffset),
                requestedOffset: pendingInitialViewportOffset,
                viewportAnchorY: pendingInitialViewportAnchorY.map {
                    String(format: "%.2f", $0)
                } ?? "nil"
            )
        }
        return nil
    }

    private func clampedContentOffset(for proposedOffset: CGPoint) -> CGPoint {
        let minimumX = -adjustedContentInset.left
        let minimumY = -adjustedContentInset.top
        let maximumX = max(
            contentSize.width + adjustedContentInset.right - bounds.width,
            minimumX
        )
        let maximumY = max(
            contentSize.height + adjustedContentInset.bottom - bounds.height,
            minimumY
        )
        return CGPoint(
            x: min(max(proposedOffset.x, minimumX), maximumX),
            y: min(max(proposedOffset.y, minimumY), maximumY)
        )
    }

}
#endif
