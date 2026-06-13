import Foundation

/// High-level native and backend intelligence capabilities that can be routed.
public enum IntelligenceCapability: String, Codable, Sendable, Equatable {
    case chat
    case titleGeneration = "title_generation"
    case audioTranscription = "audio_transcription"
    case videoTranscription = "video_transcription"
    case liveNotes = "live_notes"
    case liveVoice = "live_voice"
}

/// Provider vocabulary for route metadata without changing backend provider settings.
public enum IntelligenceProvider: String, Codable, Sendable, Equatable {
    case anthropic
    case openAI = "openai"
    case google
    case apple
}

/// Execution boundary used by a capability request.
public enum IntelligenceExecutionRoute: String, Codable, Sendable, Equatable {
    case backendGateway = "backend_gateway"
    case appleOnDevice = "apple_on_device"
    case applePCC = "apple_pcc"
    case nativeProviderPackage = "native_provider_package"
    case openAIRealtimeVoice = "openai_realtime_voice"
}

/// Credential owner or token source used by an execution route.
public enum IntelligenceCredentialSource: String, Codable, Sendable, Equatable {
    case backendBYOK = "backend_byok"
    case appleOS = "apple_os"
    case appleOSEntitlement = "apple_os_entitlement"
    case deviceKeychainOAuth = "device_keychain_oauth"
    case ephemeralBackendToken = "ephemeral_backend_token"
}

/// Model family identifier for route metadata.
public enum IntelligenceModelFamily: Codable, Sendable, Equatable {
    case systemLanguageModel
    case privateCloudComputeLanguageModel
    case externalModel(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
    }

    private enum Kind: String, Codable {
        case systemLanguageModel = "system_language_model"
        case privateCloudComputeLanguageModel = "private_cloud_compute_language_model"
        case externalModel = "external_model"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .systemLanguageModel:
            self = .systemLanguageModel
        case .privateCloudComputeLanguageModel:
            self = .privateCloudComputeLanguageModel
        case .externalModel:
            self = .externalModel(try container.decode(String.self, forKey: .identifier))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemLanguageModel:
            try container.encode(Kind.systemLanguageModel, forKey: .kind)
        case .privateCloudComputeLanguageModel:
            try container.encode(Kind.privateCloudComputeLanguageModel, forKey: .kind)
        case .externalModel(let identifier):
            try container.encode(Kind.externalModel, forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}

/// Privacy-safe failure category for intelligence route diagnostics.
public enum IntelligenceFailureCategory: String, Codable, Sendable, Equatable {
    case unavailable
    case permissionDenied = "permission_denied"
    case contextOverflow = "context_overflow"
    case structuredOutputInvalid = "structured_output_invalid"
    case cancelled
    case rateLimited = "rate_limited"
    case networkUnavailable = "network_unavailable"
    case unknown
}

/// Describes how an intelligence capability is executed.
public struct IntelligenceRouteDescriptor: Codable, Sendable, Equatable {
    public let capability: IntelligenceCapability
    public let provider: IntelligenceProvider
    public let executionRoute: IntelligenceExecutionRoute
    public let credentialSource: IntelligenceCredentialSource
    public let modelFamily: IntelligenceModelFamily

    public init(
        capability: IntelligenceCapability,
        provider: IntelligenceProvider,
        executionRoute: IntelligenceExecutionRoute,
        credentialSource: IntelligenceCredentialSource,
        modelFamily: IntelligenceModelFamily
    ) {
        self.capability = capability
        self.provider = provider
        self.executionRoute = executionRoute
        self.credentialSource = credentialSource
        self.modelFamily = modelFamily
    }

    public static func appleOnDevice(capability: IntelligenceCapability) -> Self {
        Self(
            capability: capability,
            provider: .apple,
            executionRoute: .appleOnDevice,
            credentialSource: .appleOS,
            modelFamily: .systemLanguageModel
        )
    }
}

/// Token usage and model context size for an intelligence request.
public struct IntelligenceContextBudget: Codable, Sendable, Equatable {
    public let usedTokens: Int
    public let contextSize: Int

    public init(usedTokens: Int, contextSize: Int) {
        self.usedTokens = usedTokens
        self.contextSize = contextSize
    }
}

/// Privacy-safe route metadata for diagnostics and evaluation records.
public struct IntelligenceRouteMetadata: Codable, Sendable, Equatable {
    private static let sensitiveExtraKeys: Set<String> = [
        "prompt",
        "response",
        "model_response",
        "transcript",
        "transcript_text",
        "audio",
        "raw_audio"
    ]

    public let descriptor: IntelligenceRouteDescriptor
    public let latencyMs: Int?
    public let structuredOutputValid: Bool?
    public let failureCategory: IntelligenceFailureCategory?
    public let contextBudget: IntelligenceContextBudget?
    public let extra: [String: String]

    public init(
        descriptor: IntelligenceRouteDescriptor,
        latencyMs: Int?,
        structuredOutputValid: Bool?,
        failureCategory: IntelligenceFailureCategory?,
        contextBudget: IntelligenceContextBudget?,
        extra: [String: String] = [:]
    ) {
        self.descriptor = descriptor
        self.latencyMs = latencyMs
        self.structuredOutputValid = structuredOutputValid
        self.failureCategory = failureCategory
        self.contextBudget = contextBudget
        self.extra = extra.filter { key, _ in
            !Self.sensitiveExtraKeys.contains(key.lowercased())
        }
    }
}
