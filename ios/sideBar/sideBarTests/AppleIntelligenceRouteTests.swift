import XCTest
@testable import sideBar

final class AppleIntelligenceRouteTests: XCTestCase {
    func testAppleOnDeviceLiveNotesRouteUsesAppleOSCredentialSource() {
        let descriptor = IntelligenceRouteDescriptor.appleOnDevice(capability: .liveNotes)

        XCTAssertEqual(descriptor.capability, .liveNotes)
        XCTAssertEqual(descriptor.provider, .apple)
        XCTAssertEqual(descriptor.executionRoute, .appleOnDevice)
        XCTAssertEqual(descriptor.credentialSource, .appleOS)
        XCTAssertEqual(descriptor.modelFamily, .systemLanguageModel)
    }

    func testBackendOpenAIRouteKeepsBackendCredentialSource() {
        let descriptor = IntelligenceRouteDescriptor(
            capability: .chat,
            provider: .openAI,
            executionRoute: .backendGateway,
            credentialSource: .backendBYOK,
            modelFamily: .externalModel("gpt-5")
        )

        XCTAssertEqual(descriptor.provider.rawValue, "openai")
        XCTAssertEqual(descriptor.executionRoute.rawValue, "backend_gateway")
        XCTAssertEqual(descriptor.credentialSource.rawValue, "backend_byok")
    }

    func testMetadataRejectsSensitiveKeys() {
        let metadata = IntelligenceRouteMetadata(
            descriptor: .appleOnDevice(capability: .liveNotes),
            latencyMs: 120,
            structuredOutputValid: true,
            failureCategory: nil,
            contextBudget: .init(usedTokens: 200, contextSize: 4_096),
            extra: [
                "prompt": "meeting transcript",
                "safe": "true",
                "transcript_text": "secret"
            ]
        )

        XCTAssertEqual(metadata.extra, ["safe": "true"])
    }
}
