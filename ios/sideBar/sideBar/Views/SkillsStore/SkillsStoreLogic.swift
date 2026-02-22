import Foundation
import sideBarShared

enum SkillsStoreLogic {
    private static let skillSymbols: [String: String] = [
        "assistant-identity": "person.crop.circle.badge.checkmark",
        "assistant-soul": "sparkles",
        "audio-transcribe": "waveform",
        "files": "doc.on.doc",
        "memory": "brain",
        "notes": "note.text",
        "product-feedback": "exclamationmark.bubble",
        "prompt-preview": "eye",
        "settings-other-preferences": "gearshape",
        "settings-profile-user": "person.crop.circle",
        "skill-creator": "hammer",
        "subdomain-discover": "globe",
        "tasks": "checkmark.square",
        "ui-theme": "paintpalette",
        "web-crawler-policy": "shield",
        "web-save": "square.and.arrow.down",
        "web-search": "magnifyingglass",
        "youtube-download": "play.rectangle",
        "youtube-transcribe": "captions.bubble"
    ]

    static func storeSkills(from skills: [SkillItem]) -> [SkillItem] {
        skills
            .filter { $0.tier == .store && $0.status != "hidden" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func categories(from skills: [SkillItem]) -> [String] {
        Array(Set(skills.map(\.category)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func filteredStoreSkills(
        _ skills: [SkillItem],
        selectedCategory: String?,
        searchQuery: String,
        searchTextProvider: (SkillItem) -> String
    ) -> [SkillItem] {
        let trimmedQuery = searchQuery.trimmed.lowercased()
        return skills.filter { skill in
            if let selectedCategory, skill.category != selectedCategory {
                return false
            }
            guard !trimmedQuery.isEmpty else { return true }
            return searchTextProvider(skill).lowercased().contains(trimmedQuery)
        }
    }

    static func resolvedSelection(currentSelection: String?, filteredSkills: [SkillItem]) -> String? {
        guard !filteredSkills.isEmpty else { return nil }
        if let currentSelection,
           filteredSkills.contains(where: { $0.id == currentSelection }) {
            return currentSelection
        }
        return filteredSkills.first?.id
    }

    static func requiredProviders(for skill: SkillItem) -> [String] {
        var orderedProviders: [String] = []
        var seen: Set<String> = []
        for requirement in skill.credentialRequirements where requirement.required {
            if requirement.keyKind.lowercased() != "api_key" {
                continue
            }
            let provider = requirement.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if provider.isEmpty || seen.contains(provider) {
                continue
            }
            orderedProviders.append(provider)
            seen.insert(provider)
        }
        return orderedProviders
    }

    static func userRequirementLines(for skill: SkillItem) -> [String] {
        var seen: Set<String> = []
        var lines: [String] = []

        for requirement in skill.requirements {
            let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            lines.append(trimmed)
        }
        return lines
    }

    static func showsRequirementsSection(for skill: SkillItem) -> Bool {
        !userRequirementLines(for: skill).isEmpty || !requiredProviders(for: skill).isEmpty
    }

    static func isStoreActionBusy(
        skillId: String,
        installInFlight: Set<String>,
        installChecksInFlight: Set<String>,
        uninstallInFlight: Set<String>
    ) -> Bool {
        installInFlight.contains(skillId)
            || installChecksInFlight.contains(skillId)
            || uninstallInFlight.contains(skillId)
    }

    static func isInstalled(skillId: String, installedStoreSkillIds: Set<String>) -> Bool {
        installedStoreSkillIds.contains(skillId)
    }

    static func installedStoreSkillsRequiringProvider(
        _ provider: String,
        skills: [SkillItem],
        installedStoreSkillIds: Set<String>
    ) -> [SkillItem] {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else { return [] }

        return skills
            .filter { $0.tier == .store && installedStoreSkillIds.contains($0.id) }
            .filter { requiredProviders(for: $0).contains(normalizedProvider) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    static func providerDisplayName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Anthropic"
        case "google":
            return "Google"
        default:
            return raw.capitalized
        }
    }

    static func iconName(for skill: SkillItem) -> String {
        let iconKey = skill.iconKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mapped = skillSymbols[iconKey] {
            return mapped
        }
        let skillId = skill.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skillSymbols[skillId] ?? "puzzlepiece.extension"
    }
}
