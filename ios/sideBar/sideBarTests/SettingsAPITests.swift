import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsAPITests: XCTestCase {
    override func tearDown() {
        SettingsURLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testGetSettingsDecodesResponse() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": "friendly",
              "working_relationship": null,
              "name": "User",
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "assistant_identity": {
                "name": "sideBar",
                "tone": "direct",
                "values": "clarity",
                "boundaries": "no guessing"
              },
              "assistant_soul": {
                "purpose": "Help with durable progress.",
                "operating_principles": "Be direct and clear.",
                "adaptation_policy": "Adapt on repeated feedback.",
                "success_signals": "Less rework."
              },
              "assistant_soul_meta": {
                "updated_at": "2026-02-17T10:00:00Z",
                "version": 1,
                "reason": "Bootstrap initialization"
              },
              "ai_primary_provider": "openai",
              "ai_primary_provider_has_key": true,
              "ai_primary_provider_key_last4": "1234",
              "enabled_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.getSettings()

        XCTAssertEqual(settings.userId, "u1")
        XCTAssertEqual(settings.communicationStyle, "friendly")
        XCTAssertEqual(settings.assistantIdentity?.name, "sideBar")
        XCTAssertEqual(settings.assistantSoul?.purpose, "Help with durable progress.")
        XCTAssertEqual(settings.assistantSoulMeta?.version, 1)
        XCTAssertEqual(settings.aiPrimaryProvider, "openai")
        XCTAssertTrue(settings.aiPrimaryProviderHasKey)
        XCTAssertEqual(settings.aiPrimaryProviderKeyLast4, "1234")
    }

    func testUpdateSettingsUsesPatchWithSnakeCaseKeys() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url?.absoluteString.contains("settings") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(body["communication_style"] as? String, "brief")
            XCTAssertEqual(body["enabled_skills"] as? [String], ["s1"])
            XCTAssertFalse(body.keys.contains("assistant_identity"))
            XCTAssertNil(body["communicationStyle"])
            XCTAssertNil(body["enabledSkills"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": "brief",
              "working_relationship": null,
              "name": null,
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "assistant_identity": {
                "name": "sideBar",
                "tone": "direct",
                "values": "clarity",
                "boundaries": "no guessing"
              },
              "enabled_skills": ["s1"]
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.updateSettings(
            SettingsUpdate(
                communicationStyle: "brief",
                enabledSkills: ["s1"]
            )
        )

        XCTAssertEqual(settings.communicationStyle, "brief")
        XCTAssertEqual(settings.enabledSkills, ["s1"])
        XCTAssertEqual(settings.assistantIdentity?.boundaries, "no guessing")
    }

    func testUpdateSettingsEncodesNullDateOfBirthWhenIncluded() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertTrue(body.keys.contains("date_of_birth"))
            XCTAssertTrue(body["date_of_birth"] is NSNull)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "user_id": "u1",
              "communication_style": null,
              "working_relationship": null,
              "name": null,
              "job_title": null,
              "employer": null,
              "date_of_birth": null,
              "gender": null,
              "pronouns": null,
              "location": null,
              "profile_image_url": null,
              "assistant_identity": null,
              "enabled_skills": []
            }
            """
            return (response, Data(payload.utf8))
        }

        _ = try await api.updateSettings(
            SettingsUpdate(dateOfBirth: nil, includeDateOfBirth: true)
        )
    }

    func testRotateShortcutsTokenUsesPost() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/shortcuts/pat/rotate") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"token\":\"abc\"}".utf8))
        }

        let response = try await api.rotateShortcutsToken()

        XCTAssertEqual(response.token, "abc")
    }

    func testGetProviderKeyStatusUsesProviderQuery() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/ai/provider-key") == true)
            XCTAssertTrue(request.url?.absoluteString.contains("provider=openai") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"provider\":\"openai\",\"has_key\":true,\"key_last4\":\"5678\"}".utf8))
        }

        let status = try await api.getProviderKeyStatus(provider: "openai")

        XCTAssertEqual(status.provider, "openai")
        XCTAssertTrue(status.hasKey)
        XCTAssertEqual(status.keyLast4, "5678")
    }

    func testUpsertProviderKeyUsesPutAndApiKeyBody() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/ai/provider-key") == true)
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(body["provider"] as? String, "anthropic")
            XCTAssertEqual(body["api_key"] as? String, "sk-ant-test")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"provider\":\"anthropic\",\"has_key\":true,\"key_last4\":\"9999\"}".utf8))
        }

        let status = try await api.upsertProviderKey(provider: "anthropic", apiKey: "sk-ant-test")

        XCTAssertEqual(status.provider, "anthropic")
        XCTAssertTrue(status.hasKey)
        XCTAssertEqual(status.keyLast4, "9999")
    }

    func testDeleteProviderKeyUsesDeleteWithQuery() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/ai/provider-key") == true)
            XCTAssertTrue(request.url?.absoluteString.contains("provider=google") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{\"provider\":\"google\",\"has_key\":false,\"key_last4\":null}".utf8))
        }

        let status = try await api.deleteProviderKey(provider: "google")

        XCTAssertEqual(status.provider, "google")
        XCTAssertFalse(status.hasKey)
        XCTAssertNil(status.keyLast4)
    }

    func testGetProfileImageUsesRequestData() async throws {
        let api = SettingsAPI(client: makeClient())
        let expected = Data([0x01, 0x02])
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, expected)
        }

        let data = try await api.getProfileImage()

        XCTAssertEqual(data, expected)
    }

    func testUploadProfileImageSetsHeaders() async throws {
        let api = SettingsAPI(client: makeClient(), session: makeSession())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Filename"), "avatar.png")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.uploadProfileImage(
            data: Data([0x01, 0x02]),
            contentType: "image/png",
            filename: "avatar.png"
        )
    }

    func testDeleteProfileImageUsesDelete() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("settings/profile-image") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        try await api.deleteProfileImage()
    }

    private func makeClient() -> APIClient {
        let config = APIClientConfig(
            baseUrl: URL(string: "https://example.com")!,
            accessTokenProvider: { nil }
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsURLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        return APIClient(config: config, session: session)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsURLProtocolMock.self]
        return URLSession(configuration: configuration)
    }
}

extension SettingsAPITests {
    func testDisconnectProviderConsumerUsesPostWithSourceAndSkillID() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.contains("settings/ai/provider-key/disconnect") == true
            )
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(body["provider"] as? String, "openai")
            XCTAssertEqual(body["source"] as? String, "skill")
            XCTAssertEqual(body["skill_id"] as? String, "audio-transcribe")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "provider": "openai",
              "source": "skill",
              "actions": {
                "disabled_skill_ids": ["audio-transcribe"],
                "detached_ai_provider": false,
                "deleted_provider_key": false
              },
              "remaining_consumers": {
                "ai_provider": true,
                "skill_ids": []
              },
              "settings": {
                "enabled_skills": ["notes"],
                "installed_store_skills": ["audio-transcribe"],
                "ai_primary_provider": "openai"
              }
            }
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.disconnectProviderConsumer(
            provider: "openai",
            source: .skill,
            skillId: "audio-transcribe"
        )

        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.source, .skill)
        XCTAssertEqual(result.actions.disabledSkillIds, ["audio-transcribe"])
        XCTAssertFalse(result.actions.deletedProviderKey)
        XCTAssertTrue(result.remainingConsumers.aiProvider)
    }

    func testDisconnectProviderConsumerUsesAiProviderSourceWithoutSkillID() async throws {
        let api = SettingsAPI(client: makeClient())
        SettingsURLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(
                request.url?.absoluteString.contains("settings/ai/provider-key/disconnect") == true
            )
            let bodyData = try XCTUnwrap(request.httpBodyData())
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            )
            XCTAssertEqual(body["provider"] as? String, "openai")
            XCTAssertEqual(body["source"] as? String, "ai_provider")
            XCTAssertNil(body["skill_id"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = """
            {
              "provider": "openai",
              "source": "ai_provider",
              "actions": {
                "disabled_skill_ids": [],
                "detached_ai_provider": true,
                "deleted_provider_key": false
              },
              "remaining_consumers": {
                "ai_provider": false,
                "skill_ids": ["audio-transcribe"]
              },
              "settings": {
                "enabled_skills": ["audio-transcribe"],
                "installed_store_skills": ["audio-transcribe"],
                "ai_primary_provider": null
              }
            }
            """
            return (response, Data(payload.utf8))
        }

        let result = try await api.disconnectProviderConsumer(
            provider: "openai",
            source: .aiProvider,
            skillId: nil
        )

        XCTAssertEqual(result.source, .aiProvider)
        XCTAssertTrue(result.actions.detachedAIProvider)
        XCTAssertEqual(result.remainingConsumers.skillIds, ["audio-transcribe"])
        XCTAssertNil(result.settings.aiPrimaryProvider)
    }
}

final class SettingsURLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = SettingsURLProtocolMock.requestHandler else {
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
