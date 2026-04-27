import Combine
import Foundation

/// Generic loading state container for async operations.
public enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    public var error: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Shared list loading state for content panels.
public enum ContentListLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    public var canShowEmptyState: Bool {
        if case .loaded = self { return true }
        return false
    }

    public static func failure(message: String?) -> ContentListLoadState {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedMessage, !trimmedMessage.isEmpty else {
            return .failed("Unable to load content")
        }
        return .failed(trimmedMessage)
    }
}

/// Base class for ViewModels with common loading/error state.
@MainActor
open class LoadableViewModel: ObservableObject {
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String?

    public init() {
    }

    public func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    public func setError(_ error: Error?) {
        errorMessage = error.map { ErrorMapping.message(for: $0) }
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Execute an async operation with automatic loading/error state management.
    public func withLoading<T>(
        _ operation: () async throws -> T,
        onSuccess: ((T) -> Void)? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await operation()
            onSuccess?(result)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
        isLoading = false
    }
}
