import SwiftUI

struct SoulCalibrationPromptView: View {
    let state: OnboardingCalibrationState
    let confirmationText: String?
    let errorMessage: String?
    let isBusy: Bool
    let onSubmitPrimaryGoals: ([String]) -> Void
    let onSubmitWorkingRelationship: (String) -> Void
    let onSubmitTonePreferences: ([String]) -> Void
    let onAcceptName: () -> Void
    let onRegenerateName: () -> Void

    @State private var selectedPrimaryGoals: Set<String> = []
    @State private var selectedWorkingRelationship: String?
    @State private var selectedToneChoices: [Int: String] = [:]
    @State private var displayStepOverride: CalibrationDisplayStep?

    private let primaryGoalOptions: [CalibrationChoice] = [
        .init(label: "Personal productivity", value: "personal_productivity"),
        .init(label: "Work productivity", value: "work_productivity"),
        .init(label: "Planning and tasks", value: "planning_and_tasks"),
        .init(label: "Notes and ideas", value: "notes_and_ideas"),
        .init(label: "Life admin", value: "life_admin"),
        .init(label: "Learning and research", value: "learning_and_research")
    ]

    private let workingRelationshipOptions: [CalibrationChoice] = [
        .init(label: "Just help when I ask", value: "just_help_when_i_ask"),
        .init(label: "Keep me on track", value: "keep_me_on_track"),
        .init(label: "Take initiative with me", value: "take_initiative_with_me")
    ]

    private let tonePairs: [(left: CalibrationChoice, right: CalibrationChoice)] = [
        (.init(label: "Warm", value: "warm"), .init(label: "Direct", value: "direct")),
        (.init(label: "Playful", value: "playful"), .init(label: "Serious", value: "serious")),
        (.init(label: "Concise", value: "concise"), .init(label: "Expressive", value: "expressive")),
        (.init(label: "Formal", value: "formal"), .init(label: "Casual", value: "casual")),
        (.init(label: "Supportive", value: "supportive"), .init(label: "Challenging", value: "challenging"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            setupLabel
            headline

            if let supportingCopy {
                Text(supportingCopy)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let helperCopy {
                Text(helperCopy)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.Spacing.xxxs)
            }

            if state.status == .awaitingNameAcceptance, let confirmationText {
                Text(confirmationText)
                    .appFont(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            promptContent

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .padding(.top, DesignTokens.Spacing.xxxs)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
        .onAppear(perform: syncSelectionsFromState)
        .onChange(of: state, initial: false) { _, _ in
            syncSelectionsFromState()
        }
    }

    private var setupLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "person.crop.circle")
                .appFont(.captionSemibold)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("SIDEBAR SETUP")
                .appFont(.captionSemibold)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, DesignTokens.Spacing.xxxs)
    }

    private var headline: some View {
        Text(headlineText)
            .appFont(.title3Semibold)
            .foregroundStyle(.primary)
    }

    private var headlineText: String {
        switch displayedStep {
        case .nameConfirmation:
            if let proposedName = state.proposedName {
                return "Hello, I'm \(proposedName)"
            }
            return "Hello"
        case .primaryGoal:
            return "What should I help you with?"
        case .workingRelationship:
            return "How should I work with you?"
        case .tonePreferences:
            return "How should I sound?"
        }
    }

    private var supportingCopy: String? {
        switch displayedStep {
        case .nameConfirmation:
            return state.proposedName.map { "I'd like to go by \($0)." }
        case .primaryGoal:
            return "Choose one or more areas you want me to focus on."
        case .workingRelationship:
            return "Choose the way you want me to work with you."
        case .tonePreferences:
            return "Choose the tone that feels more like what you want from me."
        }
    }

    private var helperCopy: String? {
        guard displayedStep == .tonePreferences else {
            return nil
        }
        return "Pick one option in each row."
    }

    @ViewBuilder
    private var promptContent: some View {
        switch displayedStep {
        case .nameConfirmation:
            nameConfirmationContent
        case .primaryGoal:
            primaryGoalContent
        case .workingRelationship:
            workingRelationshipContent
        case .tonePreferences:
            tonePreferencesContent
        }
    }

    private var primaryGoalContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            FlexibleChipLayout(spacing: DesignTokens.Spacing.sm, lineSpacing: DesignTokens.Spacing.sm) {
                ForEach(primaryGoalOptions) { option in
                    let isSelected = selectedPrimaryGoals.contains(option.value)
                    let hasReachedSelectionLimit = selectedPrimaryGoals.count >= 3
                    let isEnabled = !isBusy && (isSelected || !hasReachedSelectionLimit)

                    SoulCalibrationChoiceChip(
                        title: option.label,
                        isSelected: isSelected,
                        isEnabled: isEnabled
                    ) {
                        togglePrimaryGoal(option.value)
                    }
                }
            }

            continueButton(
                isEnabled: !selectedPrimaryGoals.isEmpty,
                action: submitPrimaryGoals
            )
        }
    }

    private var workingRelationshipContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            FlexibleChipLayout(spacing: DesignTokens.Spacing.sm, lineSpacing: DesignTokens.Spacing.sm) {
                ForEach(workingRelationshipOptions) { option in
                    SoulCalibrationChoiceChip(
                        title: option.label,
                        isSelected: selectedWorkingRelationship == option.value,
                        isEnabled: !isBusy
                    ) {
                        selectedWorkingRelationship = option.value
                    }
                }
            }

            continueButton(
                isEnabled: selectedWorkingRelationship != nil,
                action: submitWorkingRelationship
            )
        }
    }

    private var tonePreferencesContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                ForEach(Array(tonePairs.enumerated()), id: \.offset) { index, pair in
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        SoulCalibrationChoiceChip(
                            title: pair.left.label,
                            isSelected: selectedToneChoices[index] == pair.left.value,
                            isEnabled: !isBusy
                        ) {
                            selectedToneChoices[index] = pair.left.value
                        }

                        Text("vs")
                            .appFont(.captionSemibold)
                            .foregroundStyle(.secondary)

                        SoulCalibrationChoiceChip(
                            title: pair.right.label,
                            isSelected: selectedToneChoices[index] == pair.right.value,
                            isEnabled: !isBusy
                        ) {
                            selectedToneChoices[index] = pair.right.value
                        }
                    }
                }
            }

            continueButton(
                isEnabled: selectedToneChoices.count == tonePairs.count,
                action: submitTonePreferences
            )
        }
    }

    private var nameConfirmationContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if canGoBack {
                Button("Back") {
                    goBack()
                }
                .buttonStyle(.plain)
                .appFont(.bodySemibold)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back")
            }

            Spacer()

            SoulCalibrationChoiceChip(
                title: "Try another",
                isSelected: false,
                isEnabled: !isBusy
            ) {
                onRegenerateName()
            }

            ContinueButton(
                title: "Hello!",
                isEnabled: !isBusy,
                action: onAcceptName
            )
        }
    }

    private func continueButton(isEnabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if canGoBack {
                Button("Back") {
                    goBack()
                }
                .buttonStyle(.plain)
                .appFont(.bodySemibold)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back")
            }

            Spacer()

            ContinueButton(
                title: "Continue",
                isEnabled: isEnabled && !isBusy,
                action: action
            )
        }
    }

    private func togglePrimaryGoal(_ value: String) {
        if selectedPrimaryGoals.contains(value) {
            selectedPrimaryGoals.remove(value)
            return
        }

        guard selectedPrimaryGoals.count < 3 else {
            return
        }
        selectedPrimaryGoals.insert(value)
    }

    private func submitPrimaryGoals() {
        guard !selectedPrimaryGoals.isEmpty else {
            return
        }

        displayStepOverride = .workingRelationship
        let ordered = primaryGoalOptions
            .map(\.value)
            .filter { selectedPrimaryGoals.contains($0) }
        onSubmitPrimaryGoals(ordered)
    }

    private func submitWorkingRelationship() {
        guard let selectedWorkingRelationship else {
            return
        }
        displayStepOverride = .tonePreferences
        onSubmitWorkingRelationship(selectedWorkingRelationship)
    }

    private func submitTonePreferences() {
        guard selectedToneChoices.count == tonePairs.count else {
            return
        }

        let ordered = tonePairs.indices.compactMap { selectedToneChoices[$0] }
        onSubmitTonePreferences(ordered)
    }

    private func syncSelectionsFromState() {
        let resolvedStep = resolvedDisplayStep
        if let displayStepOverride {
            if displayStepOverride == resolvedStep {
                self.displayStepOverride = nil
            } else if displayStepOverride.progressIndex > resolvedStep.progressIndex, !isBusy {
                self.displayStepOverride = nil
            }
        }

        selectedPrimaryGoals = Set(
            (state.answers.primaryGoal ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        selectedWorkingRelationship = state.answers.workingRelationship

        let storedTones = (state.answers.tonePreferences ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        selectedToneChoices = Dictionary(
            uniqueKeysWithValues: storedTones.enumerated().map { ($0.offset, $0.element) }
        )
    }

    private var displayedStep: CalibrationDisplayStep {
        displayStepOverride ?? resolvedDisplayStep
    }

    private var resolvedDisplayStep: CalibrationDisplayStep {
        if state.status == .awaitingNameAcceptance {
            return .nameConfirmation
        }
        return CalibrationDisplayStep(prompt: state.currentPrompt)
    }

    private var canGoBack: Bool {
        displayedStep.previous != nil
    }

    private func goBack() {
        guard let previous = displayedStep.previous else {
            return
        }
        displayStepOverride = previous
    }
}
