import XCTest
@testable import sideBar

final class LanguageModelServicingTests: XCTestCase {
    func testFakeServiceReturnsConfiguredStructuredOutput() async throws {
        struct Output: Codable, Equatable {
            let decision: String
        }

        let service = FakeLanguageModelService()
        service.enqueue(result: .success(.init(
            routeMetadata: .init(
                descriptor: .appleOnDevice(capability: .liveNotes),
                latencyMs: 10,
                structuredOutputValid: true,
                failureCategory: nil,
                contextBudget: .init(usedTokens: 12, contextSize: 4_096)
            ),
            outputData: try JSONEncoder().encode(Output(decision: "no_change"))
        )))

        let result: LanguageModelResult<Output> = try await service.generate(
            LanguageModelRequest(
                capability: .liveNotes,
                instructions: "Classify the chunk.",
                input: "Repeated discussion.",
                route: .appleOnDevice(capability: .liveNotes)
            ),
            as: Output.self
        )

        XCTAssertEqual(result.output, Output(decision: "no_change"))
        XCTAssertEqual(result.routeMetadata.structuredOutputValid, true)
    }

    func testFakeServiceRecordsRequestsWithoutPersistingPromptInMetadata() async throws {
        struct Output: Codable, Equatable {
            let value: String
        }

        let service = FakeLanguageModelService()
        service.enqueue(result: .success(.init(
            routeMetadata: .init(
                descriptor: .appleOnDevice(capability: .liveNotes),
                latencyMs: nil,
                structuredOutputValid: true,
                failureCategory: nil,
                contextBudget: nil,
                extra: ["prompt": "secret", "safe": "true"]
            ),
            outputData: try JSONEncoder().encode(Output(value: "ok"))
        )))

        let result: LanguageModelResult<Output> = try await service.generate(
            LanguageModelRequest(
                capability: .liveNotes,
                instructions: "Secret instructions",
                input: "Secret input",
                route: .appleOnDevice(capability: .liveNotes)
            ),
            as: Output.self
        )

        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(result.routeMetadata.extra, ["safe": "true"])
    }
}
