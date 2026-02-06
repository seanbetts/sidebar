import { browser } from '$app/environment';
import { writable } from 'svelte/store';

/** Temperature display unit for weather in the site header. */
export type WeatherUnit = 'celsius' | 'fahrenheit';

const weatherUsesFahrenheitKey = 'sidebar.weatherUsesFahrenheit';

function normalizeWeatherUnit(value: unknown): WeatherUnit {
	return value === 'fahrenheit' ? 'fahrenheit' : 'celsius';
}

function toStoredValue(unit: WeatherUnit): string {
	return unit === 'fahrenheit' ? 'true' : 'false';
}

function readStoredWeatherUnit(): WeatherUnit {
	if (!browser) {
		return 'celsius';
	}

	return localStorage.getItem(weatherUsesFahrenheitKey) === 'true' ? 'fahrenheit' : 'celsius';
}

/**
 * Create a local persisted weather-preferences store.
 *
 * @returns Store with subscribe and setter methods.
 */
function createWeatherPreferencesStore() {
	const { subscribe, set } = writable<WeatherUnit>(readStoredWeatherUnit());

	return {
		subscribe,
		setWeatherUnit(unit: WeatherUnit) {
			const normalized = normalizeWeatherUnit(unit);
			if (browser) {
				localStorage.setItem(weatherUsesFahrenheitKey, toStoredValue(normalized));
			}
			set(normalized);
		},
		refreshFromStorage() {
			set(readStoredWeatherUnit());
		}
	};
}

/** Client-side weather preference store (parity with native app storage behavior). */
export const weatherPreferencesStore = createWeatherPreferencesStore();
