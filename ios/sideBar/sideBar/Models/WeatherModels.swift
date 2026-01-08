import Foundation

public struct WeatherResponse: Codable {
    public let temperatureC: Double
    public let feelsLikeC: Double
    public let weatherCode: Int
    public let isDay: Int
    public let windSpeedKph: Double?
    public let windDirectionDegrees: Double?
    public let precipitationMm: Double?
    public let cloudCoverPercent: Double?
    public let daily: [WeatherDailySummary]
    public let fetchedAt: Double
}

public struct WeatherDailySummary: Codable {
    public let weatherCode: Int
    public let temperatureMaxC: Double
    public let temperatureMinC: Double
    public let precipitationProbabilityMax: Double?
}
