import Foundation
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

/// Manages places autocomplete and reverse geocoding state.
@MainActor public final class PlacesViewModel: LoadableViewModel {
    @Published public private(set) var predictions: [PlacePrediction] = []
    @Published public private(set) var reverseLabel: String?

    private let api: PlacesAPI

    public init(api: PlacesAPI) {
        self.api = api
    }

    public func autocomplete(query: String) async {
        clearError()
        do {
            let response = try await api.autocomplete(query: query)
            predictions = response.predictions
        } catch {
            setError(error)
        }
    }

    public func reverse(lat: Double, lon: Double) async {
        clearError()
        do {
            let response = try await api.reverse(lat: lat, lon: lon)
            reverseLabel = response.label
        } catch {
            setError(error)
        }
    }
}
