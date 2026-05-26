import SwiftUI
import sideBarShared
#if os(macOS)
import AppKit

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadTextView {
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

    func activateEditingIfNeeded(at point: NSPoint) {
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
