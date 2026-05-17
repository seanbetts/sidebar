import XCTest
@testable import sideBar
import sideBarShared

final class SkillsStoreLogicTests: XCTestCase {
    func testStoreSkillsFiltersAndSortsVisibleStoreSkills() {
        let skills = [
            makeSkill(id: "alpha", name: "Alpha", tier: .store, status: "active"),
            makeSkill(id: "hidden", name: "Hidden", tier: .store, status: "hidden"),
            makeSkill(id: "notes", name: "Notes", tier: .standard, status: "active"),
            makeSkill(id: "beta", name: "Beta", tier: .store, status: "beta")
        ]

        let result = SkillsStoreLogic.storeSkills(from: skills)

        XCTAssertEqual(result.map(\.id), ["alpha", "beta"])
    }

    func testFilteredStoreSkillsAppliesCategoryAndSearchQuery() {
        let skills = [
            makeSkill(id: "audio", name: "Audio Transcribe", category: "Media", tier: .store),
            makeSkill(id: "youtube", name: "YouTube", category: "Media", tier: .store),
            makeSkill(id: "crawler", name: "Web Crawler", category: "Web", tier: .store)
        ]

        let result = SkillsStoreLogic.filteredStoreSkills(
            skills,
            selectedCategory: "Media",
            searchQuery: "youtube"
        ) { skill in
            "\(skill.name) \(skill.description) \(skill.category)"
        }

        XCTAssertEqual(result.map(\.id), ["youtube"])
    }

    func testResolvedSelectionPrefersExistingValidSelection() {
        let filtered = [
            makeSkill(id: "a", name: "A", tier: .store),
            makeSkill(id: "b", name: "B", tier: .store)
        ]

        let result = SkillsStoreLogic.resolvedSelection(currentSelection: "b", filteredSkills: filtered)

        XCTAssertEqual(result, "b")
    }

    func testResolvedSelectionFallsBackToFirstFilteredSkill() {
        let filtered = [
            makeSkill(id: "first", name: "First", tier: .store),
            makeSkill(id: "second", name: "Second", tier: .store)
        ]

        let result = SkillsStoreLogic.resolvedSelection(currentSelection: "missing", filteredSkills: filtered)

        XCTAssertEqual(result, "first")
    }

    func testRequiredProvidersNormalizesDeduplicatesAndFiltersNonApiRequirements() {
        let skill = makeSkill(
            id: "audio-transcribe",
            name: "Audio Transcribe",
            tier: .store,
            credentialRequirements: [
                SkillCredentialRequirement(provider: " OpenAI ", keyKind: "api_key", required: true),
                SkillCredentialRequirement(provider: "openai", keyKind: "api_key", required: true),
                SkillCredentialRequirement(provider: "google", keyKind: "oauth", required: true),
                SkillCredentialRequirement(provider: "anthropic", keyKind: "api_key", required: false)
            ]
        )

        let providers = SkillsStoreLogic.requiredProviders(for: skill)

        XCTAssertEqual(providers, ["openai"])
    }

    func testUserRequirementLinesTrimsDeduplicatesAndDropsEmptyValues() {
        let skill = makeSkill(
            id: "crawler",
            name: "Web Crawler",
            tier: .store,
            requirements: [
                "  A domain to analyze  ",
                "",
                "a DOMAIN to analyze",
                "A publicly accessible URL"
            ]
        )

        let lines = SkillsStoreLogic.userRequirementLines(for: skill)

        XCTAssertEqual(lines, ["A domain to analyze", "A publicly accessible URL"])
    }

    func testShowsRequirementsSectionWhenUserRequirementsExistWithoutCredentials() {
        let skill = makeSkill(
            id: "crawler",
            name: "Web Crawler",
            tier: .store,
            requirements: ["A domain to analyze"]
        )

        XCTAssertTrue(SkillsStoreLogic.showsRequirementsSection(for: skill))
    }

    func testShowsRequirementsSectionWhenCredentialRequirementsExistWithoutUserRequirements() {
        let skill = makeSkill(
            id: "audio",
            name: "Audio",
            tier: .store,
            credentialRequirements: [SkillCredentialRequirement(provider: "openai", required: true)]
        )

        XCTAssertTrue(SkillsStoreLogic.showsRequirementsSection(for: skill))
    }

    func testShowsRequirementsSectionFalseWhenNoRequirementsExist() {
        let skill = makeSkill(id: "notes", name: "Notes", tier: .store)

        XCTAssertFalse(SkillsStoreLogic.showsRequirementsSection(for: skill))
    }

    func testIsStoreActionBusyTrueWhenAnyActionSetContainsSkill() {
        XCTAssertTrue(
            SkillsStoreLogic.isStoreActionBusy(
                skillId: "skill-1",
                installInFlight: ["skill-1"],
                installChecksInFlight: [],
                uninstallInFlight: []
            )
        )
        XCTAssertTrue(
            SkillsStoreLogic.isStoreActionBusy(
                skillId: "skill-1",
                installInFlight: [],
                installChecksInFlight: ["skill-1"],
                uninstallInFlight: []
            )
        )
        XCTAssertTrue(
            SkillsStoreLogic.isStoreActionBusy(
                skillId: "skill-1",
                installInFlight: [],
                installChecksInFlight: [],
                uninstallInFlight: ["skill-1"]
            )
        )
        XCTAssertFalse(
            SkillsStoreLogic.isStoreActionBusy(
                skillId: "skill-1",
                installInFlight: [],
                installChecksInFlight: [],
                uninstallInFlight: []
            )
        )
    }

    func testIsInstalledUsesInstalledStoreSkillSetMembership() {
        let installedSkillIds: Set<String> = ["audio", "youtube"]
        XCTAssertTrue(SkillsStoreLogic.isInstalled(skillId: "audio", installedStoreSkillIds: installedSkillIds))
        XCTAssertFalse(SkillsStoreLogic.isInstalled(skillId: "notes", installedStoreSkillIds: installedSkillIds))
    }

    func testProviderDisplayNameFormatsKnownAndUnknownProviders() {
        XCTAssertEqual(SkillsStoreLogic.providerDisplayName("openai"), "OpenAI")
        XCTAssertEqual(SkillsStoreLogic.providerDisplayName("anthropic"), "Anthropic")
        XCTAssertEqual(SkillsStoreLogic.providerDisplayName("google"), "Google")
        XCTAssertEqual(SkillsStoreLogic.providerDisplayName("custom_provider"), "Custom_Provider")
    }

    func testInstalledStoreSkillsRequiringProviderFiltersInstalledAndSortsByName() {
        let skills = [
            makeSkill(
                id: "planner",
                name: "Planner",
                tier: .store,
                credentialRequirements: [SkillCredentialRequirement(provider: "openai", required: true)]
            ),
            makeSkill(
                id: "audio",
                name: "Audio",
                tier: .store,
                credentialRequirements: [SkillCredentialRequirement(provider: "google", required: true)]
            ),
            makeSkill(
                id: "briefs",
                name: "Briefs",
                tier: .store,
                credentialRequirements: [SkillCredentialRequirement(provider: "openai", required: true)]
            ),
            makeSkill(
                id: "standard",
                name: "Standard",
                tier: .standard,
                credentialRequirements: [SkillCredentialRequirement(provider: "openai", required: true)]
            )
        ]

        let installed = Set(["planner", "briefs", "audio"])
        let result = SkillsStoreLogic.installedStoreSkillsRequiringProvider(
            " OpenAI ",
            skills: skills,
            installedStoreSkillIds: installed
        )

        XCTAssertEqual(result.map(\.id), ["briefs", "planner"])
    }

    func testAppIconUsesKnownMappingsAndFallback() {
        let mapped = makeSkill(id: "audio-transcribe", name: "Audio", tier: .store)
        XCTAssertEqual(SkillsStoreLogic.appIcon(for: mapped), AppIcon.Media.waveform)

        let unknown = makeSkill(id: "unknown-skill", name: "Unknown", tier: .store)
        XCTAssertEqual(SkillsStoreLogic.appIcon(for: unknown), AppIcon.Skills.fallback)
    }

    private func makeSkill(
        id: String,
        name: String,
        description: String = "Description",
        category: String = "General",
        tier: SkillTier = .standard,
        status: String = "active",
        credentialRequirements: [SkillCredentialRequirement] = [],
        requirements: [String] = []
    ) -> SkillItem {
        SkillItem(
            id: id,
            name: name,
            description: description,
            category: category,
            tier: tier,
            credentialRequirements: credentialRequirements,
            installable: tier == .store,
            status: status,
            requirements: requirements
        )
    }
}
