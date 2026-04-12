import SwiftUI

struct HeaderStatusPillButton: View {
    let pill: HeaderStatusPillModel
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) async -> HeaderStatusRowActionResult

    @State private var isPresented = false
    @State private var actionState = HeaderStatusActionPresentationState()
    @State private var popoverState: HeaderStatusPopoverState

    init(
        pill: HeaderStatusPillModel,
        onAction: @escaping (HeaderStatusRowModel, HeaderStatusActionModel) async -> HeaderStatusRowActionResult = { _, _ in
            .retained
        }
    ) {
        self.pill = pill
        self.onAction = onAction
        _popoverState = State(initialValue: HeaderStatusPopoverState(rows: pill.popover.rows))
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                pillLeadingAccessory
                Text(pill.label)
                    .appFont(.captionSemibold)
                    .foregroundStyle(.secondary)
            }
            .pillStyle()
        }
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        .accessibilityLabel(pill.accessibilityLabel)
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            MacPopoverShell {
                HeaderStatusPopover(
                    model: pill.popover,
                    actionState: actionState,
                    popoverState: popoverState,
                    onAction: handleAction
                )
            }
            .presentationCompactAdaptation(.sheet)
        }
    }

    @ViewBuilder
    private var pillLeadingAccessory: some View {
        switch pill.tone {
        case .progress:
            LoadingIndicatorView(size: LoadingIndicatorSize.inline)
        case .warning:
            Circle()
                .fill(DesignTokens.Colors.warning)
                .frame(width: 8, height: 8)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.error)
        case .success:
            SuccessCheckBadge(size: 14, symbolSize: 8)
        }
    }

    private func handleAction(row: HeaderStatusRowModel, action: HeaderStatusActionModel) {
        guard !actionState.isDisabled(rowID: row.id, actionID: action.id) else {
            return
        }

        actionState = HeaderStatusActionPresentationState(
            inFlightActionID: action.id,
            inFlightRowID: row.id
        )

        Task {
            let result = await onAction(row, action)
            await MainActor.run {
                actionState = HeaderStatusActionPresentationState()

                switch result {
                case .resolved:
                    popoverState = popoverState.removingResolvedRow(id: row.id)
                    if popoverState.shouldDismiss {
                        isPresented = false
                    }
                case .retained:
                    break
                case let .failed(message):
                    popoverState = popoverState.applyingFailure(rowID: row.id, message: message)
                }
            }
        }
    }
}
