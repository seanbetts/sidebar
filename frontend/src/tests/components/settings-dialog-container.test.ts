import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { describe, expect, it, beforeEach, vi } from 'vitest';
import SettingsDialogContainer from '$lib/components/left-sidebar/panels/SettingsDialogContainer.svelte';
import { dispatchSettingsRealtimeUpdate } from '$lib/utils/settingsRealtime';

const { fetchSettings, fetchSkills, weatherPreferencesStore } = vi.hoisted(() => {
	const createStore = <T>(initial: T) => {
		let value = initial;
		const subscribers = new Set<(next: T) => void>();
		return {
			subscribe(run: (next: T) => void) {
				run(value);
				subscribers.add(run);
				return () => subscribers.delete(run);
			},
			set(next: T) {
				value = next;
				subscribers.forEach((fn) => fn(value));
			}
		};
	};

	return {
		fetchSettings: vi.fn(),
		fetchSkills: vi.fn(),
		weatherPreferencesStore: {
			...createStore<'celsius' | 'fahrenheit'>('celsius'),
			refreshFromStorage: vi.fn(),
			setWeatherUnit: vi.fn()
		}
	};
});

vi.mock('$lib/components/left-sidebar/panels/settingsApi', () => ({
	fetchSettings,
	fetchSkills,
	fetchLocationSuggestions: vi.fn(),
	installSkill: vi.fn(),
	uninstallSkill: vi.fn(),
	saveSettings: vi.fn(),
	uploadProfileImage: vi.fn(),
	deleteProfileImage: vi.fn()
}));

vi.mock('$lib/stores/weatherPreferences', () => ({
	weatherPreferencesStore,
	type: {}
}));

vi.mock('$lib/utils/errorHandling', () => ({
	logError: vi.fn()
}));

describe('SettingsDialogContainer', () => {
	beforeEach(() => {
		vi.clearAllMocks();
		fetchSettings.mockResolvedValue({
			communication_style: 'Initial style',
			working_relationship: 'Initial relationship',
			assistant_identity: { name: 'sideBar' },
			assistant_identity_meta: { version: 1 },
			assistant_soul: { purpose: 'Initial purpose' },
			assistant_soul_meta: { version: 1 },
			name: 'Sean',
			job_title: '',
			employer: '',
			date_of_birth: '',
			gender: '',
			pronouns: '',
			location: '',
			profile_image_url: '',
			enabled_skills: []
		});
		fetchSkills.mockResolvedValue([]);
	});

	it('applies realtime assistant and profile settings updates while open', async () => {
		render(SettingsDialogContainer, {
			open: true,
			profileImageSrc: ''
		});

		await waitFor(() => {
			expect((screen.getByLabelText('Name') as HTMLInputElement).value).toBe('Sean');
		});

		dispatchSettingsRealtimeUpdate({
			assistant_identity: { name: 'Updated Assistant' },
			assistant_soul: { purpose: 'Updated purpose' }
		});
		dispatchSettingsRealtimeUpdate({
			name: 'Updated Sean',
			communication_style: 'Updated style',
			profile_image_url: 'https://example.com/profile.png'
		});

		await waitFor(() => {
			expect((screen.getByLabelText('Name') as HTMLInputElement).value).toBe('Updated Sean');
		});

		await fireEvent.click(screen.getByRole('button', { name: 'User' }));

		await waitFor(() => {
			expect((screen.getByLabelText('Communication style') as HTMLTextAreaElement).value).toBe(
				'Updated style'
			);
		});

		await fireEvent.click(screen.getByRole('button', { name: 'Agent' }));

		await waitFor(() => {
			expect((screen.getByLabelText('Assistant name') as HTMLInputElement).value).toBe(
				'Updated Assistant'
			);
			expect(
				(screen.getByLabelText("Updated Assistant's Purpose") as HTMLTextAreaElement).value
			).toBe('Updated purpose');
		});

		await fireEvent.click(screen.getByRole('button', { name: 'Account' }));

		await waitFor(() => {
			expect(screen.getByAltText('Profile')).toHaveAttribute(
				'src',
				expect.stringContaining('https://example.com/profile.png')
			);
		});
	});
});
