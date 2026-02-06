import { fireEvent, render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import SettingsSystemSection from '$lib/components/left-sidebar/panels/settings/SettingsSystemSection.svelte';

describe('SettingsSystemSection', () => {
	it('updates weather units via callback', async () => {
		const setWeatherUnit = vi.fn();
		render(SettingsSystemSection, {
			communicationStyle: '',
			workingRelationship: '',
			weatherUnit: 'celsius',
			setWeatherUnit,
			isLoadingSettings: false,
			settingsError: ''
		});

		const select = screen.getByLabelText('Temperature units') as HTMLSelectElement;
		await fireEvent.change(select, { target: { value: 'fahrenheit' } });

		expect(setWeatherUnit).toHaveBeenCalledWith('fahrenheit');
	});
});
