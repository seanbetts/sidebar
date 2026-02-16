import { render, screen } from '@testing-library/svelte';
import { describe, expect, it } from 'vitest';
import SettingsAgentSection from '$lib/components/left-sidebar/panels/settings/SettingsAgentSection.svelte';

describe('SettingsAgentSection', () => {
	it('renders assistant identity fields as read-only', () => {
		render(SettingsAgentSection, {
			assistantIdentityName: 'sideBar',
			assistantIdentityTone: 'Pragmatic and direct.',
			assistantIdentityValues: 'Clarity first.',
			assistantIdentityBoundaries: 'Never fabricate.'
		});

		const assistantName = screen.getByLabelText('Assistant name') as HTMLInputElement;
		const assistantTone = screen.getByLabelText('Assistant tone') as HTMLTextAreaElement;

		expect(assistantName.value).toBe('sideBar');
		expect(assistantName).toHaveAttribute('readonly');
		expect(assistantTone).toHaveAttribute('readonly');
	});
});
