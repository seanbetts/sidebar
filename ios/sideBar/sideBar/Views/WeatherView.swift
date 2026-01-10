import SwiftUI

public struct WeatherView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        WeatherDetailView(
            weatherViewModel: environment.weatherViewModel,
            settingsViewModel: environment.settingsViewModel
        )
    }
}

private struct WeatherDetailView: View {
    @ObservedObject var weatherViewModel: WeatherViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    await settingsViewModel.load()
                    await loadWeatherIfPossible()
                }
            }
        }
        .onChange(of: settingsViewModel.settings?.location) { _, _ in
            Task { await loadWeatherIfPossible() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(.headline)
                if let location = settingsViewModel.settings?.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if weatherViewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = weatherViewModel.errorMessage {
            PlaceholderView(title: error)
        } else if settingsViewModel.settings?.location?.trimmed.isEmpty ?? true {
            PlaceholderView(title: "Set a location in Settings to view weather.")
        } else if let weather = weatherViewModel.weather {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    currentWeatherCard(weather: weather)
                    forecastList(weather: weather)
                }
                .padding(20)
            }
        } else {
            PlaceholderView(title: "No weather data yet.")
        }
    }

    private func currentWeatherCard(weather: WeatherResponse) -> some View {
        let tempText = temperatureText(weather.temperatureC)
        let feelsText = temperatureText(weather.feelsLikeC)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: iconName(for: weather.weatherCode, isDay: weather.isDay == 1))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tempText)
                        .font(.title2.weight(.semibold))
                    Text("Feels like \(feelsText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 16) {
                if let windSpeed = weather.windSpeedKph {
                    Label("\(Int(round(windSpeed))) kph", systemImage: "wind")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let precipitation = weather.precipitationMm {
                    Label("\(Int(round(precipitation))) mm", systemImage: "drop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let cloud = weather.cloudCoverPercent {
                    Label("\(Int(round(cloud)))%", systemImage: "cloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private func forecastList(weather: WeatherResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Forecast")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(weather.daily.enumerated()), id: \.offset) { index, day in
                HStack {
                    Text("Day \(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(temperatureText(day.temperatureMinC)) / \(temperatureText(day.temperatureMaxC))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                if index != weather.daily.count - 1 {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private func loadWeatherIfPossible() async {
        guard let location = settingsViewModel.settings?.location?.trimmed, !location.isEmpty else {
            return
        }
        await weatherViewModel.load(location: location)
    }

    private func temperatureText(_ celsius: Double) -> String {
        let c = Int(round(celsius))
        let f = Int(round(celsius * 9 / 5 + 32))
        return "\(c)°C / \(f)°F"
    }

    private func iconName(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sun.max" : "moon.stars"
        case 1, 2, 3:
            return isDay ? "cloud.sun" : "cloud.moon"
        case 45, 48:
            return "cloud.fog"
        case 51, 53, 55, 56, 57:
            return "cloud.drizzle"
        case 61, 63, 65, 66, 67:
            return "cloud.rain"
        case 71, 73, 75, 77:
            return "cloud.snow"
        case 80, 81, 82:
            return "cloud.heavyrain"
        case 95, 96, 99:
            return "cloud.bolt.rain"
        default:
            return "cloud"
        }
    }

    private var cardBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var cardBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
