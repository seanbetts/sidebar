import Foundation
import sideBarShared
import SwiftUI

struct ChatToolActionListView: View {
    let actions: [ChatToolAction]
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                ChatToolActionCard(action: action, onAction: onAction)
            }
        }
    }
}

struct ChatToolActionCard: View {
    let action: ChatToolAction
    let onAction: (ChatToolAction, ChatToolActionDecision?) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        switch action.kind {
        case .confirmation:
            confirmationControls
        case .undo:
            undoCard
        }
    }

    private var undoCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xsPlus) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                SkillSymbolIcon(
                    systemName: iconName,
                    appFontStyle: .subheadline,
                    foreground: iconForeground
                )
                .frame(width: DesignTokens.Icon.md, height: DesignTokens.Icon.md)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displaySummary)
                        .appFont(.subheadlineSemibold)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let supportingText {
                        Text(supportingText)
                            .appFont(.caption)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DesignTokens.Spacing.xs)
            }
            undoControls
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xsPlus, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var confirmationControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Decline",
                systemImage: "xmark",
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, .decline)
            }

            actionButton(
                title: "Confirm",
                systemImage: "checkmark",
                foreground: primaryButtonForeground,
                background: primaryButtonBackground
            ) {
                onAction(action, .accept)
            }

            statusLabel
        }
    }

    private var undoControls: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            actionButton(
                title: "Undo",
                systemImage: "arrow.uturn.backward",
                foreground: secondaryButtonForeground,
                background: secondaryButtonBackground
            ) {
                onAction(action, nil)
            }

            statusLabel
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action handler: @escaping () -> Void
    ) -> some View {
        Button(action: handler) {
            Label(title, systemImage: systemImage)
                .appFont(.subheadlineSemibold)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxsPlus)
                .frame(minHeight: DesignTokens.Size.compactFieldHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isPending)
        .opacity(isPending ? 1 : 0.62)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if action.status != .pending {
            Text(statusText)
                .appFont(.captionSemibold)
                .foregroundStyle(statusForeground)
        }
    }

    private var supportingText: String? {
        if action.status == .running {
            return "Working..."
        }
        if action.status == .failed {
            return "Action failed. Try again."
        }
        if let guardReason = normalizedGuardReason {
            return guardReason
        }
        if action.kind == .confirmation, action.undoSupported {
            return "You can undo this briefly after it runs."
        }
        return nil
    }

    private var normalizedGuardReason: String? {
        guard let guardReason = action.guardReason?.trimmedOrNil else {
            return nil
        }
        if guardReason == "destructive_action" {
            return action.undoSupported
                ? "This deletes content. You can undo this briefly after it runs."
                : "This deletes content."
        }
        return guardReason.replacingOccurrences(of: "_", with: " ")
    }

    private var displaySummary: String {
        guard action.kind == .confirmation,
              let toolName = action.toolName?.trimmedOrNil,
              toolName.lowercased().hasPrefix("delete ") else {
            return action.summary
        }
        let deletedObject = toolName
            .dropFirst("Delete ".count)
            .lowercased()
        guard !deletedObject.isEmpty else {
            return action.summary
        }
        return "Delete this \(deletedObject)?"
    }

    private var iconName: String {
        switch action.kind {
        case .confirmation:
            return "exclamationmark.triangle"
        case .undo:
            return "arrow.uturn.backward.circle"
        }
    }

    private var iconForeground: Color {
        if action.status == .failed {
            return DesignTokens.Colors.error
        }
        return action.kind == .confirmation ? DesignTokens.Colors.warning : DesignTokens.Colors.textSecondary
    }

    private var isPending: Bool {
        action.status == .pending
    }

    private var statusText: String {
        switch action.status {
        case .pending:
            return ""
        case .running:
            return "Working"
        case .accepted:
            return "Confirmed"
        case .declined:
            return "Declined"
        case .undone:
            return "Undone"
        case .failed:
            return "Failed"
        }
    }

    private var statusForeground: Color {
        action.status == .failed ? DesignTokens.Colors.error : DesignTokens.Colors.textSecondary
    }

    private var cardBackground: Color {
        switch action.kind {
        case .confirmation:
            return action.status == .failed
                ? DesignTokens.Colors.errorBackground
                : DesignTokens.Colors.warningBackground
        case .undo:
            return DesignTokens.Colors.successBackground
        }
    }

    private var cardBorder: Color {
        switch action.kind {
        case .confirmation:
            return action.status == .failed
                ? DesignTokens.Colors.errorBorder
                : DesignTokens.Colors.warningBorder
        case .undo:
            return DesignTokens.Colors.successBorder
        }
    }

    private var primaryButtonBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var primaryButtonForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var secondaryButtonBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var secondaryButtonForeground: Color {
        DesignTokens.Colors.textPrimary
    }
}
