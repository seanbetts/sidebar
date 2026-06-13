import Foundation

// swiftlint:disable type_name

/// Feature flags that gate sideBar's Apple Intelligence execution paths.
public struct AppleIntelligenceFeatureFlags: Sendable, Equatable {
    public let localModelsEnabled: Bool
    public let pccEnabled: Bool

    public init(localModelsEnabled: Bool = false, pccEnabled: Bool = false) {
        self.localModelsEnabled = localModelsEnabled
        self.pccEnabled = pccEnabled
    }
}

/// Runtime framework support detected by the native app.
public struct AppleIntelligenceRuntimeSupport: Sendable, Equatable {
    public let supportsFoundationModels: Bool
    public let supportsSpeechTranscription: Bool

    public init(supportsFoundationModels: Bool, supportsSpeechTranscription: Bool) {
        self.supportsFoundationModels = supportsFoundationModels
        self.supportsSpeechTranscription = supportsSpeechTranscription
    }
}

/// Reason an Apple Intelligence capability cannot use a local execution path.
public enum AppleIntelligenceUnavailableReason: String, Sendable, Equatable {
    case localModelsFlagDisabled
    case pccFlagDisabled
    case foundationModelsUnavailable
    case speechTranscriptionUnavailable
}

/// Computed availability for one intelligence capability.
public struct AppleIntelligenceAvailability: Sendable, Equatable {
    public let capability: IntelligenceCapability
    public let canUseOnDeviceLanguageModel: Bool
    public let canUsePCC: Bool
    public let canUseSpeechTranscription: Bool
    public let reasons: Set<AppleIntelligenceUnavailableReason>

    public init(
        capability: IntelligenceCapability,
        canUseOnDeviceLanguageModel: Bool,
        canUsePCC: Bool,
        canUseSpeechTranscription: Bool,
        reasons: Set<AppleIntelligenceUnavailableReason>
    ) {
        self.capability = capability
        self.canUseOnDeviceLanguageModel = canUseOnDeviceLanguageModel
        self.canUsePCC = canUsePCC
        self.canUseSpeechTranscription = canUseSpeechTranscription
        self.reasons = reasons
    }
}

/// Provides Apple Intelligence availability for native capability routing.
public protocol AppleIntelligenceAvailabilityProviding: Sendable {
    func availability(for capability: IntelligenceCapability) -> AppleIntelligenceAvailability
}

/// Deterministic availability provider for tests and injected runtime state.
public struct StaticAppleIntelligenceAvailabilityProvider: AppleIntelligenceAvailabilityProviding {
    public let flags: AppleIntelligenceFeatureFlags
    public let runtime: AppleIntelligenceRuntimeSupport

    public init(flags: AppleIntelligenceFeatureFlags, runtime: AppleIntelligenceRuntimeSupport) {
        self.flags = flags
        self.runtime = runtime
    }

    public func availability(for capability: IntelligenceCapability) -> AppleIntelligenceAvailability {
        let supportsOnDeviceLanguageModel = Self.supportsOnDeviceLanguageModel(capability)
        let supportsPCC = Self.supportsPCC(capability)
        let supportsSpeechTranscription = Self.supportsSpeechTranscription(capability)

        var reasons = Set<AppleIntelligenceUnavailableReason>()
        if supportsOnDeviceLanguageModel && !flags.localModelsEnabled {
            reasons.insert(.localModelsFlagDisabled)
        }
        if supportsPCC && !flags.pccEnabled {
            reasons.insert(.pccFlagDisabled)
        }
        if (supportsOnDeviceLanguageModel || supportsPCC) && !runtime.supportsFoundationModels {
            reasons.insert(.foundationModelsUnavailable)
        }
        if supportsSpeechTranscription && !runtime.supportsSpeechTranscription {
            reasons.insert(.speechTranscriptionUnavailable)
        }

        return AppleIntelligenceAvailability(
            capability: capability,
            canUseOnDeviceLanguageModel: supportsOnDeviceLanguageModel
                && flags.localModelsEnabled
                && runtime.supportsFoundationModels,
            canUsePCC: supportsPCC && flags.pccEnabled && runtime.supportsFoundationModels,
            canUseSpeechTranscription: supportsSpeechTranscription && runtime.supportsSpeechTranscription,
            reasons: reasons
        )
    }

    private static func supportsOnDeviceLanguageModel(_ capability: IntelligenceCapability) -> Bool {
        switch capability {
        case .chat, .titleGeneration, .liveNotes, .liveVoice:
            true
        case .audioTranscription, .videoTranscription:
            false
        }
    }

    private static func supportsPCC(_ capability: IntelligenceCapability) -> Bool {
        switch capability {
        case .liveNotes:
            true
        case .chat, .titleGeneration, .audioTranscription, .videoTranscription, .liveVoice:
            false
        }
    }

    private static func supportsSpeechTranscription(_ capability: IntelligenceCapability) -> Bool {
        switch capability {
        case .audioTranscription, .videoTranscription, .liveNotes, .liveVoice:
            true
        case .chat, .titleGeneration:
            false
        }
    }
}

/// Availability provider backed by sideBar flags and compile-time framework presence checks.
///
/// This provider does not perform entitlement, device, model-download, locale, or permission checks.
public struct DefaultAppleIntelligenceAvailabilityProvider: AppleIntelligenceAvailabilityProviding {
    public let flags: AppleIntelligenceFeatureFlags

    public init(flags: AppleIntelligenceFeatureFlags = .init()) {
        self.flags = flags
    }

    public func availability(for capability: IntelligenceCapability) -> AppleIntelligenceAvailability {
        StaticAppleIntelligenceAvailabilityProvider(
            flags: flags,
            runtime: .init(
                supportsFoundationModels: Self.supportsFoundationModels,
                supportsSpeechTranscription: Self.supportsSpeechTranscription
            )
        )
        .availability(for: capability)
    }

    private static var supportsFoundationModels: Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    private static var supportsSpeechTranscription: Bool {
        #if canImport(Speech)
        return true
        #else
        return false
        #endif
    }
}

// swiftlint:enable type_name
