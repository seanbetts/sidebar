import type { WeatherUnit } from '$lib/stores/weatherPreferences';

/**
 * Convert Celsius to Fahrenheit.
 *
 * @param celsius - Temperature in Celsius.
 * @returns Temperature in Fahrenheit.
 */
export function celsiusToFahrenheit(celsius: number): number {
	return celsius * 1.8 + 32;
}

/**
 * Format a weather temperature for display in the requested unit.
 *
 * @param celsius - Temperature in Celsius.
 * @param unit - Preferred display unit.
 * @returns Human-readable weather string.
 */
export function formatTemperature(celsius: number, unit: WeatherUnit): string {
	if (unit === 'fahrenheit') {
		return `${Math.round(celsiusToFahrenheit(celsius))}°F`;
	}
	return `${Math.round(celsius)}°C`;
}
