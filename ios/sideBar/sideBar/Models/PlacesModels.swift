import Foundation

/// Represents a place autocomplete response struct.
public struct PlaceAutocompleteResponse: Codable {
    /// The predictions value.
    public let predictions: [PlacePrediction]
}

/// Represents a place prediction struct.
public struct PlacePrediction: Codable, Identifiable {
    /// The description value.
    public let description: String?
    /// The place id value.
    public let placeId: String?

    /// The id value.
    public var id: String {
        placeId ?? description ?? UUID().uuidString
    }
}

/// Represents a place reverse response struct.
public struct PlaceReverseResponse: Codable {
    /// The label value.
    public let label: String?
    /// The levels value.
    public let levels: [String: String]?
}
