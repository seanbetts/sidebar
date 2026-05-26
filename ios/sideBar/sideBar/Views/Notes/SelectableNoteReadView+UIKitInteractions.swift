import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadTextView {
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
