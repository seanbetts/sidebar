import XCTest
@testable import sideBar

final class AppleIntelligenceAvailabilityTests: XCTestCase {
    func testAvailabilityRequiresFeatureFlagAndRuntimeSupport() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: true, pccEnabled: false),
            runtime: .init(supportsFoundationModels: true, supportsSpeechTranscription: true)
        )

        XCTAssertTrue(provider.availability(for: .liveNotes).canUseOnDeviceLanguageModel)
        XCTAssertFalse(provider.availability(for: .liveNotes).canUsePCC)
    }

    func testDisabledFlagBlocksOnDeviceLanguageModel() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: false, pccEnabled: true),
            runtime: .init(supportsFoundationModels: true, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .liveNotes)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertTrue(availability.reasons.contains(.localModelsFlagDisabled))
    }

    func testMissingFoundationModelsBlocksModelUse() {
        let provider = StaticAppleIntelligenceAvailabilityProvider(
            flags: .init(localModelsEnabled: true, pccEnabled: true),
            runtime: .init(supportsFoundationModels: false, supportsSpeechTranscription: true)
        )

        let availability = provider.availability(for: .liveNotes)

        XCTAssertFalse(availability.canUseOnDeviceLanguageModel)
        XCTAssertFalse(availability.canUsePCC)
        XCTAssertTrue(availability.reasons.contains(.foundationModelsUnavailable))
    }
}
