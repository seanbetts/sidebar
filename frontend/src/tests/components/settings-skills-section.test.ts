import { render, screen } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import SettingsSkillsSectionWithTooltipProvider from '../fixtures/SettingsSkillsSectionWithTooltipProvider.svelte';

describe('SettingsSkillsSection', () => {
	it('shows required skills as visible but non-toggleable', () => {
		const { container } = render(SettingsSkillsSectionWithTooltipProvider, {
			isLoadingSkills: false,
			skillsError: '',
			skills: [
				{
					id: 'assistant-identity',
					name: 'Assistant Identity',
					description: 'System-managed identity.',
					category: 'System',
					user_toggleable: false
				}
			],
			groupSkills: (
				list: Array<{
					id: string;
					name: string;
					description: string;
					category?: string;
					user_toggleable?: boolean;
				}>
			) => [['System', list]],
			enabledSkills: [],
			allSkillsEnabled: false,
			toggleAllSkills: vi.fn(),
			toggleSkill: vi.fn()
		});

		const checkboxes = container.querySelectorAll('input[type="checkbox"]');
		expect(checkboxes).toHaveLength(2);
		expect(checkboxes[0]).toBeDisabled();
		expect(checkboxes[1]).toBeDisabled();
		expect(checkboxes[1]).toBeChecked();
		expect(screen.queryByText('Required')).not.toBeInTheDocument();
	});
});
