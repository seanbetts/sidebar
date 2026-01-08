import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class PlacesViewModel: ObservableObject {
    @Published public private(set) var predictions: [PlacePrediction] = []
    @Published public private(set) var reverseLabel: String? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: PlacesAPI

    public init(api: PlacesAPI) {
        self.api = api
    }

    public func autocomplete(query: String) async {
        errorMessage = nil
        do {
            let response = try await api.autocomplete(query: query)
            predictions = response.predictions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reverse(lat: Double, lon: Double) async {
        errorMessage = nil
        do {
            let response = try await api.reverse(lat: lat, lon: lon)
            reverseLabel = response.label
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
