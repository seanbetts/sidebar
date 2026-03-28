import SwiftUI

extension NotesDetailView {
    var supportedNoteSurface: some View {
        ZStack {
            if isShowingReadSurface
                || editorViewModel.isHoldingReadSurfaceDuringEditEntry
                || isHoldingEditorSurfaceDuringReadExit {
                configuredReadSurface()
                    .zIndex(isHoldingEditorSurfaceDuringReadExit ? 1 : 0)
                    .allowsHitTesting(
                        isShowingReadSurface
                            && !editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            && !isHoldingEditorSurfaceDuringReadExit
                    )
            }

            if isShowingEditorSurface || isHoldingEditorSurfaceDuringReadExit {
                configuredEditorSurface
                    .zIndex(isHoldingEditorSurfaceDuringReadExit ? 0 : 1)
                    .opacity(
                        editorViewModel.isHoldingReadSurfaceDuringEditEntry
                            || isHoldingEditorSurfaceDuringReadExit ? 0 : 1
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
            onViewportOffsetChange: viewportOffsetHandler,
            onInitialViewportRestorationApplied: handleReadInitialViewportRestorationApplied
        )
    }

    @ViewBuilder
    var editorSurface: some View {
        configuredEditorSurface
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
            onEscape: handleEscapeKey
        )
        #endif
    }
}
