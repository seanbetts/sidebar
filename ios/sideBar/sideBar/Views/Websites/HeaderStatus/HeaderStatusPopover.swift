import SwiftUI

enum HeaderStatusRowActionResult: Equatable {
    case resolved
    case retained
    case failed(String)
}

struct HeaderStatusActionPresentationState: Equatable {
    let inFlightRowID: String?
    let inFlightActionID: String?

    init(
        inFlightActionID: String? = nil,
        inFlightRowID: String? = nil
    ) {
        self.inFlightRowID = inFlightRowID
        self.inFlightActionID = inFlightActionID
    }

    func isDisabled(actionID: String) -> Bool {
        inFlightActionID == actionID
    }

    func showsLoadingIndicator(actionID: String) -> Bool {
        inFlightActionID == actionID
    }

    func isDisabled(rowID: String, actionID: String) -> Bool {
        inFlightRowID == rowID && inFlightActionID == actionID
    }

    func showsLoadingIndicator(rowID: String, actionID: String) -> Bool {
        inFlightRowID == rowID && inFlightActionID == actionID
    }
}

struct HeaderStatusPopoverState: Equatable {
    let rows: [HeaderStatusRowModel]
    let inlineErrorByRowID: [String: String]
    let shouldDismiss: Bool

    init(
        rows: [HeaderStatusRowModel],
        inlineErrorByRowID: [String: String] = [:],
        shouldDismiss: Bool = false
    ) {
        self.rows = rows
        self.inlineErrorByRowID = inlineErrorByRowID
        self.shouldDismiss = shouldDismiss
    }

    func removingResolvedRow(id: String) -> HeaderStatusPopoverState {
        let remainingRows = rows.filter { $0.id != id }
        let remainingErrors = inlineErrorByRowID.filter { $0.key != id }

        return HeaderStatusPopoverState(
            rows: remainingRows,
            inlineErrorByRowID: remainingErrors,
            shouldDismiss: remainingRows.isEmpty
        )
    }

    func applyingFailure(rowID: String, message: String) -> HeaderStatusPopoverState {
        var nextErrors = inlineErrorByRowID
        nextErrors[rowID] = message

        return HeaderStatusPopoverState(
            rows: rows,
            inlineErrorByRowID: nextErrors,
            shouldDismiss: false
        )
    }
}

struct HeaderStatusPopover: View {
    let model: HeaderStatusPopoverModel
    let actionState: HeaderStatusActionPresentationState
    let popoverState: HeaderStatusPopoverState
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(model.title)
                .appFont(.subheadlineSemibold)

            if let message = model.message {
                Text(message)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !popoverState.rows.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xsPlus) {
                    ForEach(popoverState.rows) { row in
                        HeaderStatusRowView(
                            row: row,
                            actionState: actionState,
                            inlineError: popoverState.inlineErrorByRowID[row.id],
                            onAction: onAction
                        )
                    }
                }
                .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct HeaderStatusRowView: View {
    let row: HeaderStatusRowModel
    let actionState: HeaderStatusActionPresentationState
    let inlineError: String?
    let onAction: (HeaderStatusRowModel, HeaderStatusActionModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxsPlus) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(row.title)
                        .appFont(.captionSemibold)

                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.sm)

                if !row.actions.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(row.actions) { action in
                            Button(role: buttonRole(for: action.role)) {
                                onAction(row, action)
                            } label: {
                                Group {
                                    if actionState.showsLoadingIndicator(rowID: row.id, actionID: action.id) {
                                        ProgressView()
                                            .controlSize(.mini)
                                    } else {
                                        Text(action.title)
                                            .appFont(.captionSemibold)
                                    }
                                }
                                .frame(minWidth: 44)
                            }
                            .buttonStyle(.borderless)
                            .disabled(actionState.isDisabled(rowID: row.id, actionID: action.id))
                        }
                    }
                }
            }

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
    }

    private func buttonRole(for role: HeaderStatusActionRole) -> ButtonRole? {
        switch role {
        case .default:
            return nil
        case .cancel:
            return .cancel
        case .destructive:
            return .destructive
        }
    }
}
