import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class ChecklistMarkerTextAttachment: NSTextAttachment {
    let isChecked: Bool

    init(isChecked: Bool) {
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct SelectableNoteReadView: View {
    typealias ReadActivationTarget = NotesEditorViewModel.PendingEditSelectionTarget
    typealias ChecklistToggleHandler = (Int, Int) -> Void

    let document: NotesSemanticDocument
    let maxContentWidth: CGFloat
    var initialViewportOffset: CGPoint?
    var initialViewportAnchorTarget: ReadActivationTarget?
    var initialViewportAnchorY: CGFloat?
    var presentationGeneration: UInt64 = 0
    var onActivateEditing: ((ReadActivationTarget) -> Void)?
    var onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)?
    var onToggleChecklistItem: ChecklistToggleHandler?
    var onViewportOffsetChange: ((CGPoint) -> Void)?
    var onInitialViewportRestorationApplied: (() -> Void)?
    @AppStorage(AppStorageKeys.appTextSize) private var appTextSizeRaw = AppTextSizeOption.system.rawValue

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        initialViewportOffset: CGPoint? = nil,
        initialViewportAnchorTarget: ReadActivationTarget? = nil,
        initialViewportAnchorY: CGFloat? = nil,
        presentationGeneration: UInt64 = 0,
        onActivateEditing: ((ReadActivationTarget) -> Void)? = nil,
        onActivateEditingWithViewport: ((ReadActivationTarget, CGFloat?) -> Void)? = nil,
        onToggleChecklistItem: ChecklistToggleHandler? = nil,
        onViewportOffsetChange: ((CGPoint) -> Void)? = nil,
        onInitialViewportRestorationApplied: (() -> Void)? = nil
    ) {
        self.document = document
        self.maxContentWidth = maxContentWidth
        self.initialViewportOffset = initialViewportOffset
        self.initialViewportAnchorTarget = initialViewportAnchorTarget
        self.initialViewportAnchorY = initialViewportAnchorY
        self.presentationGeneration = presentationGeneration
        self.onActivateEditing = onActivateEditing
        self.onActivateEditingWithViewport = onActivateEditingWithViewport
        self.onToggleChecklistItem = onToggleChecklistItem
        self.onViewportOffsetChange = onViewportOffsetChange
        self.onInitialViewportRestorationApplied = onInitialViewportRestorationApplied
    }

    init(
        document: NotesSemanticDocument,
        maxContentWidth: CGFloat,
        onActivateEditing: (() -> Void)?
    ) {
        self.init(document: document, maxContentWidth: maxContentWidth, onActivateEditing: { _ in onActivateEditing?() })
    }

    var body: some View {
        let baseFontSize = Self.readBaseFontSize(for: resolvedTextSizeOption)
        PlatformSelectableNoteReadView(
            attributedContent: Self.makePlatformAttributedContent(
                from: document,
                baseFontSize: baseFontSize
            ),
            document: document,
            maxReadableContentWidth: maxContentWidth,
            initialViewportOffset: initialViewportOffset,
            initialViewportAnchorTarget: initialViewportAnchorTarget,
            initialViewportAnchorY: initialViewportAnchorY,
            presentationGeneration: presentationGeneration,
            onActivateEditing: onActivateEditing,
            onActivateEditingWithViewport: onActivateEditingWithViewport,
            onToggleChecklistItem: onToggleChecklistItem,
            onViewportOffsetChange: onViewportOffsetChange,
            onInitialViewportRestorationApplied: onInitialViewportRestorationApplied
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background)
    }

    private var resolvedTextSizeOption: AppTextSizeOption { AppTextSizeOption.resolved(from: appTextSizeRaw) }

}
