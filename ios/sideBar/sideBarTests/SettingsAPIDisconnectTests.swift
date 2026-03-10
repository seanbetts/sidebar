import XCTest
import sideBarShared
@testable import sideBar

@MainActor
extension SettingsAPITests {
    func testDisconnectProviderConsumerUsesPostWithSourceAndSkillID() async throws {
        let api = SettingsAPI(client: makeClient())
        router.setHandler { request in
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
        router.setHandler { request in
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
