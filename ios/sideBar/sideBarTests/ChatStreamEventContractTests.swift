import Foundation
import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class ChatStreamEventContractTests: ChatViewModelTestCase {
    func testCustomEventContractParsesEveryDeclaredEvent() throws {
        let eventNames = try loadCustomEventNames()
        var parser = ChatStreamParser()

        for eventName in eventNames {
            let chunk = "event: \(eventName)\ndata: {}\n\n"
            let events = parser.ingest(Data(chunk.utf8))
            XCTAssertEqual(
                events.map(\.type.rawValue),
                [eventName],
                "Expected parser coverage for custom SSE event \(eventName)"
            )
        }
    }

    func testCustomEventContractBuildsHandlerForEveryDeclaredEvent() throws {
        let viewModel = makeViewModel(
            api: ChatViewModelTestsSupport.MockConversationsAPI(listResult: .success([])),
            cache: TestCacheClient()
        )
        let declaredEvents = try Set(loadCustomEventNames())
        let handlerEvents = Set(viewModel.streamEventHandlers.keys.map(\.rawValue))

        XCTAssertEqual(
            handlerEvents.intersection(declaredEvents),
            declaredEvents,
            "Expected a ChatViewModel handler for every declared custom SSE event"
        )
    }

    private func loadCustomEventNames() throws -> [String] {
        let contractURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/contracts/chat_stream_custom_events.json")
        let data = try Data(contentsOf: contractURL)
        let contract = try JSONDecoder().decode(CustomEventContract.self, from: data)
        return contract.customEvents
    }
}

private struct CustomEventContract: Decodable {
    let customEvents: [String]

    private enum CodingKeys: String, CodingKey {
        case customEvents = "custom_events"
    }
}
