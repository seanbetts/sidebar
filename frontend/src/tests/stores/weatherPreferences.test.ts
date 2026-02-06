import { beforeEach, describe, expect, it, vi } from 'vitest';
import { get } from 'svelte/store';

vi.mock('$app/environment', () => ({ browser: true }));

describe('weatherPreferencesStore', () => {
	beforeEach(() => {
		localStorage.clear();
		vi.resetModules();
	});

	it('defaults to Celsius when no preference is stored', async () => {
		const { weatherPreferencesStore } = await import('$lib/stores/weatherPreferences');
		expect(get(weatherPreferencesStore)).toBe('celsius');
	});

	it('hydrates Fahrenheit from local storage', async () => {
		localStorage.setItem('sidebar.weatherUsesFahrenheit', 'true');
		const { weatherPreferencesStore } = await import('$lib/stores/weatherPreferences');
		expect(get(weatherPreferencesStore)).toBe('fahrenheit');
	});

	it('persists unit changes to local storage', async () => {
		const { weatherPreferencesStore } = await import('$lib/stores/weatherPreferences');

		weatherPreferencesStore.setWeatherUnit('fahrenheit');
		expect(get(weatherPreferencesStore)).toBe('fahrenheit');
		expect(localStorage.getItem('sidebar.weatherUsesFahrenheit')).toBe('true');

		weatherPreferencesStore.setWeatherUnit('celsius');
		expect(get(weatherPreferencesStore)).toBe('celsius');
		expect(localStorage.getItem('sidebar.weatherUsesFahrenheit')).toBe('false');
	});
});
