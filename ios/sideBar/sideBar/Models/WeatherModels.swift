import Foundation
import Combine

/// Represents a weather response struct.
public struct WeatherResponse: Codable {
    /// The temperature c value.
    public let temperatureC: Double
    /// The feels like c value.
    public let feelsLikeC: Double
    /// The weather code value.
    public let weatherCode: Int
    /// Indicates whether day.
    public let isDay: Int
    /// The wind speed kph value.
    public let windSpeedKph: Double?
    /// The wind direction degrees value.
    public let windDirectionDegrees: Double?
    /// The precipitation mm value.
    public let precipitationMm: Double?
    /// The cloud cover percent value.
    public let cloudCoverPercent: Double?
    /// The daily value.
    public let daily: [WeatherDailySummary]
    /// The fetched at value.
    public let fetchedAt: Double
}

/// Represents a weather daily summary struct.
public struct WeatherDailySummary: Codable {
    /// The weather code value.
    public let weatherCode: Int
    /// The temperature max c value.
    public let temperatureMaxC: Double
    /// The temperature min c value.
    public let temperatureMinC: Double
    /// The precipitation probability max value.
    public let precipitationProbabilityMax: Double?
}
