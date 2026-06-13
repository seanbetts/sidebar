import Foundation

/// Input for a native language model generation request.
public struct LanguageModelRequest: Sendable, Equatable {
    public let capability: IntelligenceCapability
    public let instructions: String
    public let input: String
    public let route: IntelligenceRouteDescriptor

    public init(
        capability: IntelligenceCapability,
        instructions: String,
        input: String,
        route: IntelligenceRouteDescriptor
    ) {
        self.capability = capability
        self.instructions = instructions
        self.input = input
        self.route = route
    }
}

/// Raw response bytes and route metadata returned by a language model service.
public struct LanguageModelRawResult: Sendable, Equatable {
    public let routeMetadata: IntelligenceRouteMetadata
    public let outputData: Data

    public init(routeMetadata: IntelligenceRouteMetadata, outputData: Data) {
        self.routeMetadata = routeMetadata
        self.outputData = outputData
    }
}

/// Decoded structured output and route metadata returned by a language model service.
public struct LanguageModelResult<Output: Decodable & Sendable>: Sendable {
    public let routeMetadata: IntelligenceRouteMetadata
    public let output: Output

    public init(routeMetadata: IntelligenceRouteMetadata, output: Output) {
        self.routeMetadata = routeMetadata
        self.output = output
    }
}

/// Deterministic error surface for language model service boundaries.
public enum LanguageModelServiceError: Error, Equatable {
    case noQueuedResult
    case generationFailed(IntelligenceFailureCategory)
    case decodingFailed
}

/// Boundary for native language model generation without binding callers to Apple frameworks.
public protocol LanguageModelServicing: Sendable {
    func generate<Output: Decodable & Sendable>(
        _ request: LanguageModelRequest,
        as outputType: Output.Type
    ) async throws -> LanguageModelResult<Output>
}

/// Deterministic fake for XCTest and injected local workflows.
public final class FakeLanguageModelService: LanguageModelServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [LanguageModelRequest] = []
    private var queuedResults: [Result<LanguageModelRawResult, LanguageModelServiceError>] = []

    public var requests: [LanguageModelRequest] {
        lock.withLock {
            recordedRequests
        }
    }

    public init() {}

    public func enqueue(result: Result<LanguageModelRawResult, LanguageModelServiceError>) {
        lock.withLock {
            queuedResults.append(result)
        }
    }

    public func generate<Output: Decodable & Sendable>(
        _ request: LanguageModelRequest,
        as outputType: Output.Type
    ) async throws -> LanguageModelResult<Output> {
        let raw = try lock.withLock {
            recordedRequests.append(request)
            guard !queuedResults.isEmpty else {
                throw LanguageModelServiceError.noQueuedResult
            }
            return try queuedResults.removeFirst().get()
        }

        guard let output = try? JSONDecoder().decode(outputType, from: raw.outputData) else {
            throw LanguageModelServiceError.decodingFailed
        }
        return LanguageModelResult(routeMetadata: raw.routeMetadata, output: output)
    }
}
