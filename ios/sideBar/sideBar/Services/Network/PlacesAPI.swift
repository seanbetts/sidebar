import Foundation
import sideBarShared

/// API client for places endpoints.
public struct PlacesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func autocomplete(query: String) async throws -> PlaceAutocompleteResponse {
        let path = APIClient.path(
            "places/autocomplete",
            queryItems: [URLQueryItem(name: "input", value: query)]
        )
        return try await client.request(path)
    }

    public func reverse(lat: Double, lon: Double) async throws -> PlaceReverseResponse {
        let path = APIClient.path(
            "places/reverse",
            queryItems: [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lng", value: String(lon))
            ]
        )
        return try await client.request(path)
    }
}
