import SwiftUI

extension NotesDetailView {
    var supportedNoteSurface: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.activeNote != nil && currentUnsupportedContent == nil {
                configuredReadSurface()
                    .zIndex(isHoldingEditorSurfaceDuringReadExit ? 0 : 0)
                    .opacity(isReadSurfaceVisibleForCurrentPresentation ? (isHoldingEditorSurfaceDuringReadExit ? 0 : 1) : 0)
                    .allowsHitTesting(
                        isShowingReadSurface
                            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            && !isHoldingEditorSurfaceDuringReadExit
                    )
                    .accessibilityHidden(!isReadSurfaceVisibleForCurrentPresentation)
            }

            if isShowingEditorSurface || isHoldingEditorSurfaceDuringReadExit {
                configuredEditorSurface
                    .zIndex(1)
                    .opacity(
                        editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            ? 0
                            : 1
                    )
                    .allowsHitTesting(
                        isShowingEditorSurface
                            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            && !isHoldingEditorSurfaceDuringReadExit
                    )
                    .accessibilityHidden(
                        editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            || isHoldingEditorSurfaceDuringReadExit
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var readSurface: some View {
        configuredReadSurface()
    }

    func configuredReadSurface(
        initialViewportOffset: CGPoint? = nil,
        initialViewportAnchorTarget: NotesEditorViewModel.PendingEditSelectionTarget? = nil,
        initialViewportAnchorY: CGFloat? = nil,
        reportsViewportOffsetChanges: Bool = true
    ) -> some View {
        let resolvedInitialViewportAnchorTarget =
            initialViewportAnchorTarget ?? editorViewModel.pendingReadSurfaceViewportAnchorTarget
        let resolvedInitialViewportAnchorY =
            initialViewportAnchorY ?? editorViewModel.pendingReadSurfaceViewportAnchorY
        let resolvedInitialViewportOffset =
            initialViewportOffset ?? editorViewModel.pendingReadSurfaceViewportOffset
        let viewportOffsetHandler = reportsViewportOffsetChanges ? handleReadViewportOffsetChange : nil
        return SelectableNoteReadView(
            document: currentReadDocument,
            maxContentWidth: contentMaxWidth,
            initialViewportOffset: resolvedInitialViewportOffset,
            initialViewportAnchorTarget: resolvedInitialViewportAnchorTarget,
            initialViewportAnchorY: resolvedInitialViewportAnchorY,
            onActivateEditing: activateReadSurfaceEditing,
            onActivateEditingWithViewport: activateReadSurfaceEditing,
            onToggleChecklistItem: handleReadSurfaceChecklistToggle,
            onViewportOffsetChange: viewportOffsetHandler,
            onInitialViewportRestorationApplied: handleReadInitialViewportRestorationApplied
        )
    }

    @ViewBuilder
    var editorSurface: some View {
        configuredEditorSurface
    }

    var isReadSurfaceVisibleForCurrentPresentation: Bool {
        isShowingReadSurface
            || editorViewModel.isHoldingReadSurfaceDuringEditEntry
            || isHoldingEditorSurfaceDuringReadExit
    }

    @ViewBuilder
    var configuredEditorSurface: some View {
        #if os(iOS)
        AttributedNoteEditorContainer(
            editorViewModel: editorViewModel,
            maxContentWidth: contentMaxWidth,
            onFormattingBarPresentationChange: handleFormattingBarPresentationChange,
            onInitialPresentationReady: {
                editorViewModel.completeEditEntryPresentationHold()
            },
            onEscape: handleEscapeKey
        )
        #else
        AttributedNoteEditorContainer(
            editorViewModel: editorViewModel,
            maxContentWidth: contentMaxWidth,
            onInitialPresentationReady: {
                editorViewModel.completeEditEntryPresentationHold()
            },
            onEscape: handleEscapeKey
        )
        #endif
    }
}
