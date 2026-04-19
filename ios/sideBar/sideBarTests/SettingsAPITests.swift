import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsAPITests: XCTestCase {
    var router: ScopedURLProtocolRouter!

    override func setUp() {
        super.setUp()
        router = ScopedURLProtocolRouter()
    }

    override func tearDown() {
        router.invalidate()
        router = nil
        super.tearDown()
    }

    func testGetSettingsDecodesResponse() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
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

    func testGetSettingsDecodesInternalDiagnosticsCapability() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
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
              "enabled_skills": [],
              "can_access_internal_diagnostics": true
            }
            """
            return (response, Data(payload.utf8))
        }

        let settings = try await api.getSettings()

        XCTAssertTrue(settings.canAccessInternalDiagnostics)
    }

    func testUpdateSettingsUsesPatchWithSnakeCaseKeys() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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
        router.setHandler { request in
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

    func testParallelSettingsClientsRouteIndependently() async throws {
        let leftRouter = ScopedURLProtocolRouter()
        let rightRouter = ScopedURLProtocolRouter()
        defer {
            leftRouter.invalidate()
            rightRouter.invalidate()
        }

        let leftAPI = SettingsAPI(client: makeClient(router: leftRouter))
        let rightAPI = SettingsAPI(client: makeClient(router: rightRouter))

        leftRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("settings") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = self.makeMinimalSettingsPayload(userID: "left")
            return (response, Data(payload.utf8))
        }
        rightRouter.setHandler { request in
            XCTAssertTrue(request.url?.absoluteString.contains("settings") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let payload = self.makeMinimalSettingsPayload(userID: "right")
            return (response, Data(payload.utf8))
        }

        let leftTask = Task { try await leftAPI.getSettings() }
        let rightTask = Task { try await rightAPI.getSettings() }
        let results = try await (leftTask.value, rightTask.value)

        XCTAssertEqual(results.0.userId, "left")
        XCTAssertEqual(results.1.userId, "right")
    }

    func makeClient(router: ScopedURLProtocolRouter? = nil) -> APIClient {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating APIClient")
        }
        let config = APIClientConfig(
            baseUrl: resolvedRouter.baseURL,
            accessTokenProvider: { nil }
        )
        let session = resolvedRouter.makeSession()
        return APIClient(config: config, session: session)
    }

    private func makeSession(router: ScopedURLProtocolRouter? = nil) -> URLSession {
        guard let resolvedRouter = router ?? self.router else {
            fatalError("Expected scoped router to be configured before creating URLSession")
        }
        return resolvedRouter.makeSession()
    }

    private func makeMinimalSettingsPayload(userID: String) -> String {
        """
        {
          "user_id": "\(userID)",
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
    }
}
