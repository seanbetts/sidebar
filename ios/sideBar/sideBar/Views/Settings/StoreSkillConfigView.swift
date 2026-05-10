import Foundation
import SwiftUI
import sideBarShared

struct StoreSkillConfigView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let skill: SkillItem
    let isStoreActionBusy: Bool
    let isInstalled: Bool
    let installError: String?
    let onInstallTap: (() -> Void)?
    let onInstalledTap: (() -> Void)?

    init(
        viewModel: SettingsViewModel,
        skill: SkillItem,
        isStoreActionBusy: Bool = false,
        isInstalled: Bool = false,
        installError: String? = nil,
        onInstallTap: (() -> Void)? = nil,
        onInstalledTap: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.skill = skill
        self.isStoreActionBusy = isStoreActionBusy
        self.isInstalled = isInstalled
        self.installError = installError
        self.onInstallTap = onInstallTap
        self.onInstalledTap = onInstalledTap
    }

    var body: some View {
        #if os(macOS)
        macInspectorBody
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                headerCard
                infoCard(title: "About") {
                    Text(skill.longDescription ?? viewModel.displayDescription(for: skill))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsRequirementsSection {
                    requirementsCard
                }

                infoCard(title: "How It Works") {
                    Text(skill.howItWorks ?? defaultHowItWorksText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                infoCard(title: "Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let version = skill.version, !version.isEmpty {
                            detailRow(title: "Version", value: version)
                        }
                        if let updated = formattedUpdatedAt {
                            detailRow(title: "Updated", value: updated)
                        }
                        if detailRowsAreEmpty {
                            Text("No version details available.")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .background(DesignTokens.Colors.background)
        #endif
    }

    #if os(macOS)
    private var macInspectorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: viewModel.displayName(for: skill),
                        message: viewModel.displayDescription(for: skill)
                    )

                    if let installError, !installError.isEmpty {
                        SettingsMacStatusBanner(message: installError, tone: .error)
                    }

                    SettingsMacActionSection(
                        title: "Availability",
                        message: "Install the skill here or review its current availability in your workspace."
                    ) {
                        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                            SkillAppIcon(systemName: SkillIconResolver.settingsIconName(for: skill))
                            Spacer()
                            if hasStoreInstallAction {
                                installActionButton
                            }
                        }
                    }
                }

                macInfoCard(
                    title: "About",
                    message: "What this skill does and when it is useful."
                ) {
                    Text(skill.longDescription ?? viewModel.displayDescription(for: skill))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                if showsRequirementsSection {
                    macRequirementsCard
                }

                macInfoCard(
                    title: "How It Works",
                    message: "A quick summary of how the workflow operates when you run it."
                ) {
                    Text(skill.howItWorks ?? defaultHowItWorksText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                macInfoCard(
                    title: "Details",
                    message: "Version and update information for this store skill."
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let version = skill.version, !version.isEmpty {
                            detailRow(title: "Version", value: version)
                        }
                        if let updated = formattedUpdatedAt {
                            detailRow(title: "Updated", value: updated)
                        }
                        if detailRowsAreEmpty {
                            Text("No version details available.")
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
    }

    @ViewBuilder
    private var macRequirementsCard: some View {
        macInfoCard(
            title: "Requirements",
            message: "Dependencies and credentials this skill needs before it can run."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !userRequirementLines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(userRequirementLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                Text(line)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if hasCredentialRequirements {
                    if !userRequirementLines.isEmpty {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Credentials")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        StoreSkillCredentialsView(
                            viewModel: viewModel,
                            skill: skill,
                            showHeader: false,
                            showEmptyState: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func macInfoCard<Content: View>(
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingsMacPanelCard {
            SettingsMacSectionIntro(title: title, message: message)
            content()
        }
    }
    #endif

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                SkillAppIcon(systemName: SkillIconResolver.settingsIconName(for: skill))

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.displayName(for: skill))
                        .appFont(.subheading)
                        .lineLimit(2)
                    Text(viewModel.displayDescription(for: skill))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasStoreInstallAction {
                    installActionButton
                }
            }

            if let installError, !installError.isEmpty {
                Text(installError)
                    .appFont(.caption)
                    .foregroundStyle(DesignTokens.Colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    private var requirementsCard: some View {
        infoCard(title: "Requirements") {
            VStack(alignment: .leading, spacing: 10) {
                if !userRequirementLines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(userRequirementLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                Text(line)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if hasCredentialRequirements {
                    if !userRequirementLines.isEmpty {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Credentials")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        StoreSkillCredentialsView(
                            viewModel: viewModel,
                            skill: skill,
                            showHeader: false,
                            showEmptyState: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func infoCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            content()
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Colors.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var installActionButton: some View {
        if isInstalled {
            Button {
                onInstalledTap?()
            } label: {
                StoreSkillInstallIcon(systemName: "checkmark.circle.fill", busy: isStoreActionBusy)
            }
            .accessibilityLabel("Installed")
            .disabled(isStoreActionBusy)
            .buttonStyle(.plain)
        } else {
            Button {
                onInstallTap?()
            } label: {
                StoreSkillInstallIcon(systemName: "plus.circle.fill", busy: isStoreActionBusy)
            }
            .accessibilityLabel("Install")
            .disabled(isStoreActionBusy)
            .buttonStyle(.plain)
        }
    }

    private var userRequirementLines: [String] {
        SkillsStoreLogic.userRequirementLines(for: skill)
    }

    private var hasStoreInstallAction: Bool {
        onInstallTap != nil || onInstalledTap != nil
    }

    private var hasCredentialRequirements: Bool {
        !credentialProviders.isEmpty
    }

    private var credentialProviders: [String] {
        SkillsStoreLogic.requiredProviders(for: skill)
    }

    private var showsRequirementsSection: Bool {
        SkillsStoreLogic.showsRequirementsSection(for: skill)
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
                .appFont(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appFont(.caption)
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

private struct StoreSkillInstallIcon: View {
    let systemName: String
    let busy: Bool

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary)
            } else {
                Image(systemName: systemName)
                    .appFont(.displayMd)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconForeground, Color.primary)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private var iconForeground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}
