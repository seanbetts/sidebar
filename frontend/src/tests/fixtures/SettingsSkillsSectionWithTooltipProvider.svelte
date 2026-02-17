<script lang="ts">
	import { TooltipProvider } from '$lib/components/ui/tooltip';
	import SettingsSkillsSection from '$lib/components/left-sidebar/panels/settings/SettingsSkillsSection.svelte';

	export let isLoadingSkills = false;
	export let skillsError = '';
	export let skills: Array<{
		id: string;
		name: string;
		description: string;
		category?: string;
		user_toggleable?: boolean;
	}> = [];
	export let groupSkills: (
		list: Array<{
			id: string;
			name: string;
			description: string;
			category?: string;
			user_toggleable?: boolean;
		}>
	) => Array<
		[
			string,
			Array<{
				id: string;
				name: string;
				description: string;
				category?: string;
				user_toggleable?: boolean;
			}>
		]
	> = () => [];
	export let enabledSkills: string[] = [];
	export let allSkillsEnabled = false;
	export let toggleAllSkills: (enabled: boolean) => void = () => {};
	export let toggleSkill: (id: string, enabled: boolean) => void = () => {};
</script>

<TooltipProvider delayDuration={0}>
	<SettingsSkillsSection
		{isLoadingSkills}
		{skillsError}
		{skills}
		{groupSkills}
		{enabledSkills}
		{allSkillsEnabled}
		{toggleAllSkills}
		{toggleSkill}
	/>
</TooltipProvider>
