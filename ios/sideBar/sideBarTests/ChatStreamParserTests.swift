import XCTest
import sideBarShared
@testable import sideBar

final class ChatStreamParserTests: XCTestCase {
    func testIngestParsesSingleEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: token\ndata: {\"text\":\"hi\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .token)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["text"] as? String, "hi")
    }

    func testIngestBuffersPartialEvent() {
        var parser = ChatStreamParser()
        let part1 = "event: token\ndata: {\"text\":\"hi\""
        let part2 = "}\n\n"

        let first = parser.ingest(Data(part1.utf8))
        XCTAssertTrue(first.isEmpty)

        let second = parser.ingest(Data(part2.utf8))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.type, .token)
    }

    func testIngestBuffersSplitUTF8AcrossChunks() {
        var parser = ChatStreamParser()
        let chunk = "event: token\ndata: {\"content\":\"🙂\"}\n\n"
        let fullData = Data(chunk.utf8)
        let emojiRange = fullData.range(of: Data("🙂".utf8))
        XCTAssertNotNil(emojiRange)
        let splitIndex = (emojiRange?.lowerBound ?? 0) + 2
        let part1 = fullData.prefix(splitIndex)
        let part2 = fullData.suffix(from: splitIndex)

        let first = parser.ingest(Data(part1))
        XCTAssertTrue(first.isEmpty)

        let second = parser.ingest(Data(part2))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.type, .token)
        let payload = second.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["content"] as? String, "🙂")
    }

    func testIngestIgnoresUnknownEventType() {
        var parser = ChatStreamParser()
        let chunk = "event: unknown\ndata: {\"text\":\"hi\"}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertTrue(events.isEmpty)
    }

    func testIngestParsesAssistantIdentityUpdatedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: assistant_identity_updated\ndata: {\"assistant_identity\":{\"name\":\"Navigator\"}}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .assistantIdentityUpdated)
        let payload = events.first?.data?.value as? [String: Any]
        let identity = payload?["assistant_identity"] as? [String: Any]
        XCTAssertEqual(identity?["name"] as? String, "Navigator")
    }

    func testIngestParsesOtherPreferencesUpdatedEvent() {
        var parser = ChatStreamParser()
        let chunk = "event: other_preferences_updated\ndata: {\"weather_unit\":\"fahrenheit\",\"biometric_unlock_enabled\":true}\n\n"

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .otherPreferencesUpdated)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["weather_unit"] as? String, "fahrenheit")
        XCTAssertEqual(payload?["biometric_unlock_enabled"] as? Bool, true)
    }

    func testIngestParsesWorkspacePatchEvent() {
        var parser = ChatStreamParser()
        let chunk = """
        event: workspace_patch
        data: {"version":1,"operations":[{"op":"swap_panes"}],"future_field":{"trace_id":"abc"}}


        """

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .workspacePatch)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["version"] as? Int, 1)
        let operations = payload?["operations"] as? [[String: Any]]
        XCTAssertEqual(operations?.first?["op"] as? String, "swap_panes")
        XCTAssertNotNil(payload?["future_field"] as? [String: Any])
    }

    func testIngestCapsOversizedPartialEventBuffer() {
        var parser = ChatStreamParser(maxBufferSize: 65_536)
        let oversizedChunk = String(repeating: "a", count: 1_200_000)

        let events = parser.ingest(Data(oversizedChunk.utf8))

        XCTAssertTrue(events.isEmpty)
        let mirroredBuffer = Mirror(reflecting: parser).children
            .first(where: { $0.label == "buffer" })?.value as? Data
        XCTAssertEqual(mirroredBuffer?.count, 65_536)
    }

    func testIngestParsesOnboardingResumeSuggestedEvent() {
        var parser = ChatStreamParser()
        let chunk = """
        event: onboarding_resume_suggested
        data: {"current_onboarding_step":"feature_discovery","provider_ready":true}


        """

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .onboardingResumeSuggested)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["current_onboarding_step"] as? String, "feature_discovery")
        XCTAssertEqual(payload?["provider_ready"] as? Bool, true)
    }

    func testIngestParsesOnboardingMilestoneCompletedEvent() {
        var parser = ChatStreamParser()
        let chunk = """
        event: onboarding_milestone_completed
        data: {"current_onboarding_step":"completed","provider_ready":true,"milestone":"secondary_tour_seen"}


        """

        let events = parser.ingest(Data(chunk.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .onboardingMilestoneCompleted)
        let payload = events.first?.data?.value as? [String: Any]
        XCTAssertEqual(payload?["milestone"] as? String, "secondary_tour_seen")
    }
}
