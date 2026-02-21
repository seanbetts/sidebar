import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SkillsAPITests: XCTestCase {
    override func tearDown() {
        SkillsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testListSkillsDecodesResponse() async throws {
        let api = SkillsAPI(client: makeClient())
        SkillsURLProtocolMock.requestHandler = { request in
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
        XCTAssertEqual(response.skills.first?.showRequiredBadge, false)
    }

    func testListSkillsDecodesUserToggleablePolicy() async throws {
        let api = SkillsAPI(client: makeClient())
        SkillsURLProtocolMock.requestHandler = { request in
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
        XCTAssertEqual(response.skills.first?.showRequiredBadge, true)
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
              "user_toggleable": false
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SkillsResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.skills.first?.id, "assistant-soul")
        XCTAssertEqual(response.skills.first?.userToggleable, false)
        XCTAssertEqual(response.skills.first?.showRequiredBadge, true)
    }

    func testSkillItemDecodesShowRequiredBadgeLegacyKey() throws {
        let payload = """
        {
          "skills": [
            {
              "id": "assistant-identity",
              "name": "Assistant Identity",
              "description": "Desc",
              "category": "System",
              "user_toggleable": false,
              "show_required_badge": false
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(SkillsResponse.self, from: Data(payload.utf8))

        XCTAssertEqual(response.skills.first?.id, "assistant-identity")
        XCTAssertEqual(response.skills.first?.showRequiredBadge, false)
    }

    func testListSkillsDecodesStoreRequirementMetadata() throws {
        let payload = """
        {
          "catalog_version": 3,
          "skills": [
            {
              "id": "audio-transcribe",
              "name": "Audio Transcription",
              "description": "Transcribe audio",
              "category": "Media",
              "tier": "store",
              "provider_dependency": "openai",
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

        XCTAssertEqual(response.catalogVersion, 3)
        XCTAssertEqual(response.skills.first?.tier, .store)
        XCTAssertEqual(response.skills.first?.providerDependency, "openai")
        XCTAssertEqual(response.skills.first?.installable, true)
        XCTAssertEqual(response.skills.first?.credentialRequirements.count, 1)
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.provider, "openai")
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.keyKind, "api_key")
        XCTAssertEqual(response.skills.first?.credentialRequirements.first?.required, true)
    }

    func testInstallStoreSkillPostsPayloadAndDecodesResponse() async throws {
        let api = SkillsAPI(client: makeClient())
        SkillsURLProtocolMock.requestHandler = { request in
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

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkillsURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }
}

final class SkillsURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = SkillsURLProtocolMock.requestHandler else {
            XCTFail("Request handler not set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
