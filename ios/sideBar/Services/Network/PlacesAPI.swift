import Foundation

public struct PlacesAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func autocomplete(query: String) async throws -> PlaceAutocompleteResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = "places/autocomplete?input=\(encoded)"
        return try await client.request(path)
    }

    public func reverse(lat: Double, lon: Double) async throws -> PlaceReverseResponse {
        let path = "places/reverse?lat=\(lat)&lng=\(lon)"
        return try await client.request(path)
    }
}
