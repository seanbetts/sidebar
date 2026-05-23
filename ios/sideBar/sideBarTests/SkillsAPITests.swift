import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SkillsAPITests: XCTestCase {
    private var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testListSkillsDecodesResponse() async throws {
        let api = SkillsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("skills") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"skills":[{"id":"s1","name":"Skill","description":"Desc","category":"General"}]}
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.list()

        XCTAssertEqual(response.skills.first?.id, "s1")
        XCTAssertEqual(response.skills.first?.userToggleable, true)
    }

    func testListSkillsDecodesUserToggleablePolicy() async throws {
        let api = SkillsAPI(client: makeClient())
        router.setHandler { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "skills": [
                {
                  "id": "assistant-identity",
                  "name": "Assistant Identity",
                  "description": "Desc",
                  "category": "System",
                  "user_toggleable": false
                }
              ]
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.list()

        XCTAssertEqual(response.skills.first?.id, "assistant-identity")
        XCTAssertEqual(response.skills.first?.userToggleable, false)
    }

    func testSkillItemDecodesLegacyUnderscoreKeyWithoutSnakeCaseStrategy() throws {
        let payload = """
        {
          "skills": [
            {
              "id": "assistant-soul",
              "name": "Assistant Soul",
              "description": "Desc",
              "category": "System",
              "settings_section": "agent",
              "user_toggleable": false
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SkillsResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.skills.first?.id, "assistant-soul")
        XCTAssertEqual(response.skills.first?.settingsSection, .agent)
        XCTAssertEqual(response.skills.first?.userToggleable, false)
    }

    func testListSkillsDecodesStoreRequirementMetadata() throws {
        let payload = """
        {
          "catalog_version": 5,
          "skills": [
            {
              "id": "audio-transcribe",
              "name": "Audio Transcription",
              "description": "Transcribe audio",
              "category": "Media",
              "tier": "store",
              "provider_dependency": "openai",
              "long_description": "Longer description.",
              "how_it_works": "Friendly explanation.",
              "requirements": ["OpenAI API key", "ffmpeg"],
              "version": "1.0.0",
              "updated_at": "2026-02-22",
              "install_count": null,
              "upvotes": null,
              "downvotes": null,
              "current_user_vote": null,
              "credential_requirements": [
                {
                  "provider": "openai",
                  "key_kind": "api_key",
                  "required": true,
                  "source": "provider_or_skill"
                }
              ],
              "installable": true,
              "default_enabled": false,
              "status": "active"
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SkillsResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.catalogVersion, 5)
        XCTAssertEqual(response.skills.first?.tier, .store)
        XCTAssertEqual(response.skills.first?.providerDependency, "openai")
        XCTAssertEqual(response.skills.first?.installable, true)
        XCTAssertEqual(response.skills.first?.longDescription, "Longer description.")
        XCTAssertEqual(response.skills.first?.howItWorks, "Friendly explanation.")
        XCTAssertEqual(response.skills.first?.requirements, ["OpenAI API key", "ffmpeg"])
        XCTAssertEqual(response.skills.first?.version, "1.0.0")
        XCTAssertEqual(response.skills.first?.updatedAt, "2026-02-22")
        XCTAssertNil(response.skills.first?.installCount)
        XCTAssertNil(response.skills.first?.upvotes)
        XCTAssertNil(response.skills.first?.downvotes)
        XCTAssertNil(response.skills.first?.currentUserVote)
        XCTAssertEqual(response.skills.first?.credentialRequirements.count, 1)
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.provider, "openai")
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.keyKind, "api_key")
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.required, true)
    }

    func testInstallStoreSkillPostsPayloadAndDecodesResponse() async throws {
        let api = SkillsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("skills/store/install") == true)

            let bodyData = try XCTUnwrap(request.httpBodyData())
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any]
            )
            XCTAssertEqual(object["skill_id"] as? String, "audio-transcribe")
            let providerKeys = try XCTUnwrap(object["provider_keys"] as? [[String: String]])
            XCTAssertEqual(providerKeys.count, 1)
            XCTAssertEqual(providerKeys.first?["provider"], "openai")
            XCTAssertEqual(providerKeys.first?["api_key"], "sk-openai-test-1234")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "skill_id": "audio-transcribe",
              "installed": true,
              "enabled": true,
              "enabled_skills": ["files", "audio-transcribe"],
              "installed_store_skills": ["audio-transcribe"]
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.installStoreSkill(
            skillId: "audio-transcribe",
            providerKeys: [StoreSkillProviderKeyInput(provider: "openai", apiKey: "sk-openai-test-1234")]
        )

        XCTAssertEqual(response.skillId, "audio-transcribe")
        XCTAssertTrue(response.installed)
        XCTAssertTrue(response.enabled)
        XCTAssertTrue(response.enabledSkills.contains("audio-transcribe"))
        XCTAssertEqual(response.installedStoreSkills, ["audio-transcribe"])
    }

    func testUninstallStoreSkillPostsPayloadAndDecodesResponse() async throws {
        let api = SkillsAPI(client: makeClient())
        router.setHandler { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("skills/store/uninstall") == true)

            let bodyData = try XCTUnwrap(request.httpBodyData())
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any]
            )
            XCTAssertEqual(object["skill_id"] as? String, "audio-transcribe")
            XCTAssertNil(object["provider_keys"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "skill_id": "audio-transcribe",
              "installed": false,
              "enabled": false,
              "enabled_skills": ["files"],
              "installed_store_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let response = try await api.uninstallStoreSkill(skillId: "audio-transcribe")

        XCTAssertEqual(response.skillId, "audio-transcribe")
        XCTAssertFalse(response.installed)
        XCTAssertFalse(response.enabled)
        XCTAssertFalse(response.enabledSkills.contains("audio-transcribe"))
        XCTAssertEqual(response.installedStoreSkills, [])
    }

    func testParallelSkillClientsRouteIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftAPI = SkillsAPI(client: makeClient(router: leftRouter))
        let rightAPI = SkillsAPI(client: makeClient(router: rightRouter))

        leftRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("skills") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"skills":[{"id":"left","name":"Left","description":"Desc","category":"General"}]}
            """
            return (response, Data(payload.utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("skills") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {"skills":[{"id":"right","name":"Right","description":"Desc","category":"General"}]}
            """
            return (response, Data(payload.utf8))
        }

        async let left = leftAPI.list()
        async let right = rightAPI.list()
        let results = try await (left, right)

        XCTAssertEqual(results.0.skills.first?.id, "left")
        XCTAssertEqual(results.1.skills.first?.id, "right")
    }

    private func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { "token-123" }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }
}
