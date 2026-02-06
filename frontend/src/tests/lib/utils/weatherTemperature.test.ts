import { describe, expect, it } from 'vitest';
import { celsiusToFahrenheit, formatTemperature } from '$lib/utils/weatherTemperature';

describe('weatherTemperature utilities', () => {
	it('converts Celsius to Fahrenheit', () => {
		expect(celsiusToFahrenheit(0)).toBe(32);
		expect(celsiusToFahrenheit(25)).toBe(77);
	});

	it('formats temperature in Celsius', () => {
		expect(formatTemperature(21.4, 'celsius')).toBe('21°C');
		expect(formatTemperature(21.6, 'celsius')).toBe('22°C');
	});

	it('formats temperature in Fahrenheit', () => {
		expect(formatTemperature(21.4, 'fahrenheit')).toBe('71°F');
		expect(formatTemperature(0, 'fahrenheit')).toBe('32°F');
	});
});
