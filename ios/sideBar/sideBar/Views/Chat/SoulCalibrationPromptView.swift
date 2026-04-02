import SwiftUI

struct SoulCalibrationPromptView: View {
    let state: OnboardingCalibrationState
    let confirmationText: String?
    let errorMessage: String?
    let isBusy: Bool
    let onSelectPrimaryGoal: (String) -> Void
    let onSelectWorkingRelationship: (String) -> Void
    let onSelectTonePreferences: ([String]) -> Void
    let onAcceptName: () -> Void
    let onRegenerateName: () -> Void

    @State private var selectedToneChoices: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(titleText)
                .appFont(.title3Semibold)
                .foregroundStyle(.primary)

            if let bodyText {
                Text(bodyText)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
            }

            if state.status == .awaitingNameAcceptance, let confirmationText {
                Text(confirmationText)
                    .appFont(.body)
                    .foregroundStyle(.primary)
            }

            promptContent

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var titleText: String {
        switch state.status {
        case .awaitingNameAcceptance:
            return "I think I know who I am now."
        case .notStarted, .inProgress, .completed:
            switch state.currentPrompt {
            case .primaryGoal:
                return "What would you most like me to help with first?"
            case .workingRelationship:
                return "How would you like me to work with you?"
            case .tonePreferences:
                return "How should I show up?"
            }
        }
    }

    private var bodyText: String? {
        guard state.status == .awaitingNameAcceptance,
              let proposedName = state.proposedName else {
            return nil
        }
        return "I'd like to go by \(proposedName)."
    }

    @ViewBuilder
    private var promptContent: some View {
        switch state.status {
        case .awaitingNameAcceptance:
            nameActions
        case .notStarted, .inProgress, .completed:
            switch state.currentPrompt {
            case .primaryGoal:
                chipWrap(primaryGoalOptions, action: onSelectPrimaryGoal)
            case .workingRelationship:
                chipWrap(workingRelationshipOptions, action: onSelectWorkingRelationship)
            case .tonePreferences:
                tonePreferencesContent
            }
        }
    }

    private func chipWrap(_ options: [String], action: @escaping (String) -> Void) -> some View {
        FlexibleChipLayout(spacing: DesignTokens.Spacing.sm, lineSpacing: DesignTokens.Spacing.sm) {
            ForEach(options, id: \.self) { option in
                SoulCalibrationChoiceChip(
                    title: option,
                    isSelected: false,
                    isEnabled: !isBusy
                ) {
                    action(option)
                }
            }
        }
    }

    private var tonePreferencesContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            ForEach(Array(tonePairs.enumerated()), id: \.offset) { index, pair in
                HStack(spacing: DesignTokens.Spacing.sm) {
                    SoulCalibrationChoiceChip(
                        title: pair.left,
                        isSelected: selectedToneChoices[index] == pair.left.lowercased(),
                        isEnabled: !isBusy
                    ) {
                        chooseTone(pair.left.lowercased(), at: index)
                    }
                    SoulCalibrationChoiceChip(
                        title: pair.right,
                        isSelected: selectedToneChoices[index] == pair.right.lowercased(),
                        isEnabled: !isBusy
                    ) {
                        chooseTone(pair.right.lowercased(), at: index)
                    }
                }
            }
        }
    }

    private var nameActions: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            SoulCalibrationChoiceChip(
                title: "Looks good",
                isSelected: false,
                isEnabled: !isBusy,
                emphasis: .primary
            ) {
                onAcceptName()
            }
            SoulCalibrationChoiceChip(
                title: "Try another",
                isSelected: false,
                isEnabled: !isBusy
            ) {
                onRegenerateName()
            }
        }
    }

    private func chooseTone(_ value: String, at index: Int) {
        selectedToneChoices[index] = value
        guard selectedToneChoices.count == tonePairs.count else {
            return
        }
        let ordered = tonePairs.indices.compactMap { selectedToneChoices[$0] }
        onSelectTonePreferences(ordered)
    }

    private var primaryGoalOptions: [String] {
        [
            "Personal productivity",
            "Work productivity",
            "Planning and tasks",
            "Notes and ideas",
            "Life admin",
            "Learning and research",
            "AI companion"
        ]
    }

    private var workingRelationshipOptions: [String] {
        [
            "Just help when I ask",
            "Keep me on track",
            "Take initiative with me"
        ]
    }

    private var tonePairs: [(left: String, right: String)] {
        [
            ("Warm", "Direct"),
            ("Playful", "Serious"),
            ("Concise", "Expressive"),
            ("Formal", "Casual"),
            ("Supportive", "Challenging")
        ]
    }
}

private struct SoulCalibrationChoiceChip: View {
    enum Emphasis {
        case standard
        case primary
    }

    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let emphasis: Emphasis
    let action: () -> Void

    init(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        emphasis: Emphasis = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.emphasis = emphasis
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.bodySemibold)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                )
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    private var backgroundColor: Color {
        if emphasis == .primary {
            return Color.accentColor.opacity(isEnabled ? 0.18 : 0.1)
        }
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        return DesignTokens.Colors.surface
    }

    private var borderColor: Color {
        if emphasis == .primary || isSelected {
            return Color.accentColor.opacity(0.4)
        }
        return DesignTokens.Colors.border
    }

    private var foregroundColor: Color {
        if emphasis == .primary || isSelected {
            return Color.accentColor
        }
        return .primary
    }
}

private struct FlexibleChipLayout<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: lineSpacing) {
            content()
        }
    }
}
