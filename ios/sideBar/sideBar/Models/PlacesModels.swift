import Foundation

public struct PlaceAutocompleteResponse: Codable {
    public let predictions: [PlacePrediction]
}

public struct PlacePrediction: Codable, Identifiable {
    public let description: String?
    public let placeId: String?

    public var id: String {
        placeId ?? description ?? UUID().uuidString
    }
}

public struct PlaceReverseResponse: Codable {
    public let label: String?
    public let levels: [String: String]?
}
