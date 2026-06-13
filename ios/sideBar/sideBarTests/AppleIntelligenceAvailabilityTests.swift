import XCTest
@testable import sideBar

final class AppleIntelligenceAvailabilityTests: XCTestCase {
    func testAvailabilityRequiresFeatureFlagAndRuntimeSupport() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: true, pccEnabled: false),
            runtime: .init(supportsFoundationModels: true, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .liveNotes)

        XCTAssertTrue(availability.canUseOnDeviceLanguageModel)
        XCTAssertFalse(availability.canUsePCC)
        XCTAssertTrue(availability.canUseSpeechTranscription)
        XCTAssertEqual(availability.reasons, [.pccFlagDisabled])
    }

    func testDisabledFlagBlocksOnDeviceLanguageModel() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: false, pccEnabled: true),
            runtime: .init(supportsFoundationModels: true, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .liveNotes)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertTrue(availability.canUsePCC)
        XCTAssertTrue(availability.canUseSpeechTranscription)
        XCTAssertEqual(availability.reasons, [.localModelsFlagDisabled])
    }

    func testMissingFoundationModelsBlocksModelUse() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: true, pccEnabled: true),
            runtime: .init(supportsFoundationModels: false, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .liveNotes)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertFalse(availability.canUsePCC)
        XCTAssertTrue(availability.canUseSpeechTranscription)
        XCTAssertEqual(availability.reasons, [.foundationModelsUnavailable])
    }

    func testAudioTranscriptionIgnoresModelAndPCCFailuresWhenSpeechIsAvailable() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: false, pccEnabled: false),
            runtime: .init(supportsFoundationModels: false, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .audioTranscription)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertFalse(availability.canUsePCC)
        XCTAssertTrue(availability.canUseSpeechTranscription)
        XCTAssertEqual(availability.reasons, [])
    }

    func testAudioTranscriptionReportsOnlySpeechSupportFailure() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: false, pccEnabled: false),
            runtime: .init(supportsFoundationModels: false, supportsSpeechTranscription: false)
        )

        let availability = provider.availability(for: .audioTranscription)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertFalse(availability.canUsePCC)
        XCTAssertFalse(availability.canUseSpeechTranscription)
        XCTAssertEqual(availability.reasons, [.speechTranscriptionUnavailable])
    }
}
