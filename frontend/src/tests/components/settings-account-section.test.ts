import { render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import SettingsAccountSection from '$lib/components/left-sidebar/panels/settings/SettingsAccountSection.svelte';

describe('SettingsAccountSection', () => {
	it('labels the location field as home location', () => {
		render(SettingsAccountSection, {
			handleProfileImageChange: vi.fn(),
			deleteProfileImage: vi.fn(),
			handleProfileImageError: vi.fn(),
			pronounOptions: [],
			handleLocationInput: vi.fn(),
			handleLocationKeydown: vi.fn(),
			handleLocationBlur: vi.fn(),
			selectLocation: vi.fn()
		});

		expect(screen.getByLabelText('Home location')).toBeInTheDocument();
	});
});
