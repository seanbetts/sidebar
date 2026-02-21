import XCTest
@testable import sideBar

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
            makeSkill(id: "youtube", name: "YouTube Download", category: "Media", tier: .store),
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

    func testRequirementLinesFormatsRequiredAndOptionalModes() {
        let skill = makeSkill(
            id: "crawler",
            name: "Web Crawler",
            tier: .store,
            credentialRequirements: [
                SkillCredentialRequirement(provider: "openai", required: true),
                SkillCredentialRequirement(provider: "google", required: false, mode: "report_mode")
            ]
        )

        let lines = SkillsStoreLogic.requirementLines(for: skill)

        XCTAssertEqual(lines[0], "Requires OpenAI API key")
        XCTAssertEqual(lines[1], "Optional Google API key (report mode)")
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

    private func makeSkill(
        id: String,
        name: String,
        description: String = "Description",
        category: String = "General",
        tier: SkillTier = .standard,
        status: String = "active",
        credentialRequirements: [SkillCredentialRequirement] = []
    ) -> SkillItem {
        SkillItem(
            id: id,
            name: name,
            description: description,
            category: category,
            tier: tier,
            credentialRequirements: credentialRequirements,
            installable: tier == .store,
            status: status
        )
    }
}
