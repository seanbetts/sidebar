import Foundation
import SwiftUI
import sideBarShared

// MARK: - Additional Settings Sections

struct SkillsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedTier: SkillsTierFilter = .standard
    @State private var selectedStoreSkill: SkillItem?

    var body: some View {
        Form {
            Section {
                Picker("Skill Type", selection: $selectedTier) {
                    ForEach(SkillsTierFilter.allCases) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Enable all", isOn: Binding(
                    get: { allSkillsEnabled },
                    set: { isEnabled in
                        Task {
                            await viewModel.setAllSkillsEnabled(
                                isEnabled,
                                scopeSkillIds: enableAllScopeSkillIds
                            )
                        }
                    }
                ))
                .disabled(
                    viewModel.isSavingSkills
                    || viewModel.isLoadingSkills
                    || viewModel.settings == nil
                    || !hasToggleableSkills
                )
            }

            if let error = viewModel.skillsError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }

            if groupedSkills.isEmpty && !viewModel.isLoadingSkills {
                Section {
                    Text("No skills available.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groupedSkills, id: \.0) { category, skills in
                    Section(category) {
                        ForEach(skills, id: \.id) { skill in
                            if selectedTier == .store {
                                storeSkillRow(skill)
                            } else {
                                skillToggleRow(skill)
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .sheet(item: $selectedStoreSkill) { skill in
            NavigationStack {
                StoreSkillConfigView(viewModel: viewModel, skill: skill)
                    .navigationTitle(viewModel.displayName(for: skill))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                selectedStoreSkill = nil
                            }
                        }
                    }
            }
            .phoneSheetGrabBarVisible()
        }
        .overlay {
            if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
    }

    private enum SkillsTierFilter: String, CaseIterable, Identifiable {
        case standard
        case store
        case required

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard:
                return "Standard"
            case .store:
                return "Store"
            case .required:
                return "Required"
            }
        }
    }

    @ViewBuilder
    private func skillLabel(_ skill: SkillItem, includeRequiredBadge: Bool = true) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: SkillsStoreLogic.iconName(for: skill))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(viewModel.displayName(for: skill))
                        .font(DesignTokens.Typography.subheadlineSemibold)

                    if includeRequiredBadge && !skill.userToggleable && skill.showRequiredBadge {
                        Text("Required")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }

                Text(viewModel.displayDescription(for: skill))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func skillToggleRow(_ skill: SkillItem) -> some View {
        Toggle(isOn: Binding(
            get: { isSkillEnabled(skill.id) },
            set: { isEnabled in
                Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
            }
        )) {
            skillLabel(skill)
        }
        .disabled(
            viewModel.isSavingSkills
            || viewModel.settings == nil
            || !skill.userToggleable
        )
    }

    private func storeSkillRow(_ skill: SkillItem) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Button {
                selectedStoreSkill = skill
            } label: {
                skillLabel(skill, includeRequiredBadge: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { isSkillEnabled(skill.id) },
                set: { isEnabled in
                    Task { await viewModel.setSkillEnabled(id: skill.id, enabled: isEnabled) }
                }
            ))
            .labelsHidden()
            .disabled(
                viewModel.isSavingSkills
                || viewModel.settings == nil
                || !skill.userToggleable
            )
        }
    }

    private var filteredSkills: [SkillItem] {
        viewModel.skills.filter { skill in
            switch selectedTier {
            case .standard:
                return skill.tier == .standard
            case .store:
                return skill.tier == .store
                    && skill.status != "hidden"
                    && isStoreSkillInstalled(skill)
            case .required:
                return skill.tier == .required
            }
        }
    }

    private var groupedSkills: [(String, [SkillItem])] {
        let grouped = Dictionary(grouping: filteredSkills) { $0.category }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]?.sorted { $0.name < $1.name } ?? [])
        }
    }

    private var enableAllScopeSkillIds: Set<String> {
        Set(
            filteredSkills
                .filter { $0.userToggleable }
                .map(\.id)
        )
    }

    private var allSkillsEnabled: Bool {
        let enabled = Set(viewModel.settings?.enabledSkills ?? [])
        let all = enableAllScopeSkillIds
        return !all.isEmpty && enabled.isSuperset(of: all)
    }

    private var hasToggleableSkills: Bool {
        !enableAllScopeSkillIds.isEmpty
    }

    private func isSkillEnabled(_ id: String) -> Bool {
        viewModel.settings?.enabledSkills.contains(id) ?? false
    }

    private func isStoreSkillInstalled(_ skill: SkillItem) -> Bool {
        viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }
}

struct StoreSkillConfigView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skill: SkillItem

    var body: some View {
        Form {
            Section("About") {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: SkillsStoreLogic.iconName(for: skill))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)
                    Text(skill.longDescription ?? viewModel.displayDescription(for: skill))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Requirements") {
                ForEach(Array(requirementLines.enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("How It Works") {
                Text(skill.howItWorks ?? defaultHowItWorksText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Details") {
                if let version = skill.version, !version.isEmpty {
                    detailRow(title: "Version", value: version)
                }
                if let updated = formattedUpdatedAt {
                    detailRow(title: "Updated", value: updated)
                }
                if detailRowsAreEmpty {
                    Text("No version details available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                StoreSkillCredentialsView(viewModel: viewModel, skill: skill)
            }
        }
    }

    private var requirementLines: [String] {
        let staticRequirements = skill.requirements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let credentialLines = SkillsStoreLogic.requirementLines(for: skill)
        var seen: Set<String> = []
        var merged: [String] = []

        for line in staticRequirements + credentialLines where !seen.contains(line) {
            seen.insert(line)
            merged.append(line)
        }

        return merged.isEmpty ? ["No special requirements"] : merged
    }

    private var defaultHowItWorksText: String {
        "This skill uses built-in tools to run the workflow and returns the results in a format you can act on quickly."
    }

    private var formattedUpdatedAt: String? {
        guard let raw = skill.updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let isoDate = Self.isoDateOnlyFormatter.date(from: raw) {
            return Self.readableDateFormatter.string(from: isoDate)
        }
        if let isoDateTime = Self.isoDateTimeNoFractionFormatter.date(from: raw) {
            return Self.readableDateFormatter.string(from: isoDateTime)
        }
        if let isoDateTime = Self.isoDateTimeFormatter.date(from: raw) {
            return Self.readableDateFormatter.string(from: isoDateTime)
        }
        return raw
    }

    private var detailRowsAreEmpty: Bool {
        (skill.version?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && formattedUpdatedAt == nil
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    private static let isoDateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateTimeNoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let readableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
