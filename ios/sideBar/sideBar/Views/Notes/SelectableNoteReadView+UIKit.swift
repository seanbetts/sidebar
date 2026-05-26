import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit

@available(iOS 26.0, macOS 26.0, *)
struct PlatformSelectableNoteReadView: UIViewRepresentable {
    let attributedContent: NSAttributedString
    let document: NotesSemanticDocument
    let maxReadableContentWidth: CGFloat
    let initialViewportOffset: CGPoint?
    let initialViewportAnchorTarget: SelectableNoteReadView.ReadActivationTarget?
    let initialViewportAnchorY: CGFloat?
    let presentationGeneration: UInt64
    let onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    let onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    let onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?
    let onViewportOffsetChange: ((CGPoint) -> Void)?
    let onInitialViewportRestorationApplied: (() -> Void)?

    func makeUIView(context: Context) -> SelectableNoteReadContainerView {
        let containerView = SelectableNoteReadContainerView()
        let textView = containerView.textView
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.adjustsFontForContentSizeCategory = false
        textView.textFormattingConfiguration = nil
        textView.textColor = .label
        textView.textContainer.lineFragmentPadding = 0
        textView.document = document
        textView.maxReadableContentWidth = maxReadableContentWidth
        textView.initialViewportOffset = initialViewportOffset
        textView.initialViewportAnchorTarget = initialViewportAnchorTarget
        textView.initialViewportAnchorY = initialViewportAnchorY
        textView.presentationGeneration = presentationGeneration
        textView.accessibilityIdentifier = "notes-read-text-view"
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.onActivateEditing = onActivateEditing
        textView.onActivateEditingWithViewport = onActivateEditingWithViewport
        textView.onToggleChecklistItem = onToggleChecklistItem
        textView.onViewportOffsetChange = onViewportOffsetChange
        textView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        textView.attributedText = attributedContent
        textView.invalidateCodeBlockBackgroundLayout()
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        containerView.onToggleChecklistItem = onToggleChecklistItem
        return containerView
    }

    func updateUIView(_ containerView: SelectableNoteReadContainerView, context: Context) {
        let readTextView = containerView.textView
        readTextView.document = document
        readTextView.maxReadableContentWidth = maxReadableContentWidth
        readTextView.initialViewportOffset = initialViewportOffset
        readTextView.initialViewportAnchorTarget = initialViewportAnchorTarget
        readTextView.initialViewportAnchorY = initialViewportAnchorY
        readTextView.presentationGeneration = presentationGeneration
        readTextView.onActivateEditing = onActivateEditing
        readTextView.onActivateEditingWithViewport = onActivateEditingWithViewport
        readTextView.onToggleChecklistItem = onToggleChecklistItem
        readTextView.onViewportOffsetChange = onViewportOffsetChange
        readTextView.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
        containerView.onActivateEditing = onActivateEditing
        containerView.onActivateEditingWithViewport = onActivateEditingWithViewport
        containerView.onToggleChecklistItem = onToggleChecklistItem
        if readTextView.attributedText.isEqual(to: attributedContent) == false {
            readTextView.attributedText = attributedContent
            readTextView.invalidateCodeBlockBackgroundLayout()
        }
        if readTextView.hasPendingInitialViewportRestoration {
            DispatchQueue.main.async { [weak readTextView] in
                guard let readTextView, readTextView.hasPendingInitialViewportRestoration else { return }
                readTextView.layoutIfNeeded()
                readTextView.applyInitialViewportOffsetIfNeeded()
            }
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class ReadActivationTapGestureRecognizer: UITapGestureRecognizer {
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        if preventingGestureRecognizer is UITapGestureRecognizer {
            return false
        }
        return super.canBePrevented(by: preventingGestureRecognizer)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        if preventedGestureRecognizer is UITapGestureRecognizer {
            return true
        }
        return super.canPrevent(preventedGestureRecognizer)
    }
}

@available(iOS 26.0, macOS 26.0, *)
final class SelectableNoteReadContainerView: UIView, UIGestureRecognizerDelegate {
    let textView = SelectableNoteReadTextView()
    var onActivateEditing: ((SelectableNoteReadView.ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((SelectableNoteReadView.ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: SelectableNoteReadView.ChecklistToggleHandler?

    private lazy var activationTapRecognizer: ReadActivationTapGestureRecognizer = {
        let recognizer = ReadActivationTapGestureRecognizer(
            target: self,
            action: #selector(handleActivationTapGesture(_:))
        )
        recognizer.numberOfTapsRequired = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        addGestureRecognizer(activationTapRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func handleActivationTapGesture(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: textView)
        guard recognizer.state == .ended else { return }
        if let checklistToggleTarget = textView.checklistToggleTarget(at: point),
           let onToggleChecklistItem {
            onToggleChecklistItem(checklistToggleTarget.blockIndex, checklistToggleTarget.itemIndex)
            return
        }
        guard let target = textView.activationTarget(at: point) else {
            return
        }
        if let onActivateEditingWithViewport {
            onActivateEditingWithViewport(
                target,
                textView.activationViewportAnchorY(at: point, target: target)
            )
        } else {
            onActivateEditing?(target)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        _ = gestureRecognizer
        _ = otherGestureRecognizer
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: textView)
        _ = gestureRecognizer
        return textView.linkAttribute(at: point) == nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension SelectableNoteReadView {
    static func viewportAnchorYForEditingActivation(
        in textView: UITextView,
        target: ReadActivationTarget,
        fallbackPoint: CGPoint? = nil
    ) -> CGFloat? {
        let resolvedTarget: ReadActivationTarget
        if let readTextView = textView as? SelectableNoteReadTextView {
            resolvedTarget = readViewportAnchorTarget(
                in: readTextView.document,
                editorTarget: target
            )
        } else {
            resolvedTarget = target
        }
        let visibleViewport = CGRect(
            origin: textView.contentOffset,
            size: textView.bounds.size
        ).inset(by: textView.adjustedContentInset)
        let viewportHeight = visibleViewport.height
        guard viewportHeight > 0 else { return nil }
        if case .characterOffset(let offset) = resolvedTarget,
           let position = textView.position(from: textView.beginningOfDocument, offset: offset) {
            let anchorY = textView.caretRect(for: position).midY - visibleViewport.minY
            if anchorY >= 0, anchorY <= viewportHeight {
                return anchorY
            }
        }
        if let fallbackPoint {
            let viewportMinY = textView.contentOffset.y + textView.adjustedContentInset.top
            return min(max(fallbackPoint.y - viewportMinY, 0), viewportHeight)
        }
        return nil
    }

    static func contentOffset(
        forViewportAnchorY viewportAnchorY: CGFloat,
        in textView: UITextView,
        target: ReadActivationTarget
    ) -> CGPoint? {
        let viewportHeight = textView.bounds.inset(by: textView.adjustedContentInset).height
        guard viewportHeight > 0 else { return nil }

        let clampedViewportAnchorY = min(max(viewportAnchorY, 0), viewportHeight)
        let targetPosition: UITextPosition?
        switch target {
        case .start:
            targetPosition = textView.beginningOfDocument
        case .characterOffset(let offset):
            targetPosition = textView.position(from: textView.beginningOfDocument, offset: offset)
        }
        guard let targetPosition else { return nil }

        let targetCaretRect = textView.caretRect(for: targetPosition)
        return CGPoint(
            x: textView.contentOffset.x,
            y: targetCaretRect.midY - clampedViewportAnchorY - textView.adjustedContentInset.top
        )
    }

    static func characterOffsetForEditingActivation(
        in textView: UITextView,
        at point: CGPoint
    ) -> Int? {
        let plainTextLength = textView.attributedText.length
        guard plainTextLength > 0 else { return 0 }
        let endRect = textView.caretRect(for: textView.endOfDocument)
        if point.y > endRect.maxY { return plainTextLength }

        guard let position = textView.closestPosition(to: point) else { return plainTextLength }

        let offset = min(
            max(textView.offset(from: textView.beginningOfDocument, to: position), 0),
            plainTextLength
        )
        let visualLineEndOffset = visualLineEndOffset(
            from: position,
            in: textView,
            plainTextLength: plainTextLength
        )

        if let visualLineEndPosition = textView.position(
            from: textView.beginningOfDocument,
            offset: visualLineEndOffset
        ) {
            let lineEndRect = textView.caretRect(for: visualLineEndPosition)
            if point.x > lineEndRect.maxX {
                return visualLineEndOffset
            }
        }

        return offset
    }

    static func visualLineEndOffset(
        from position: UITextPosition,
        in textView: UITextView,
        plainTextLength: Int
    ) -> Int {
        var currentPosition = position
        var currentRect = textView.caretRect(for: position)
        var currentOffset = min(
            max(textView.offset(from: textView.beginningOfDocument, to: position), 0),
            plainTextLength
        )

        while currentOffset < plainTextLength,
              let nextPosition = textView.position(from: currentPosition, offset: 1) {
            let nextOffset = min(
                max(textView.offset(from: textView.beginningOfDocument, to: nextPosition), 0),
                plainTextLength
            )
            let nextRect = textView.caretRect(for: nextPosition)
            guard abs(nextRect.midY - currentRect.midY) <= 0.5 else { break }
            currentPosition = nextPosition
            currentRect = nextRect
            currentOffset = nextOffset
        }

        return currentOffset
    }
}
#endif
