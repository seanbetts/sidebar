<script lang="ts">
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
	import { LOADING_SIZES } from '$lib/components/loading/loadingSizes';
	import { onMount } from 'svelte';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { TOOLTIP_COPY } from '$lib/constants/tooltips';
	import { canShowTooltips } from '$lib/utils/tooltip';
	import type { SkillItem } from '$lib/types/skills';

	export let isLoadingSkills = false;
	export let skillsError = '';
	export let skills: SkillItem[] = [];
	export let groupSkills: (list: SkillItem[]) => Array<[string, SkillItem[]]>;
	export let enabledSkills: string[] = [];
	export let allSkillsEnabled = false;
	export let toggleAllSkills: (enabled: boolean) => void;
	export let toggleSkill: (id: string, enabled: boolean) => void;
	export let onOpenDetail: ((skill: SkillItem) => void) | undefined = undefined;

	type TierFilter = 'all' | 'standard' | 'store' | 'required';

	let tooltipsEnabled = false;
	let hasToggleableSkills = false;
	let activeTier: TierFilter = 'all';

	onMount(() => {
		tooltipsEnabled = canShowTooltips();
	});

	$: hasToggleableSkills = skills.some((skill) => skill.user_toggleable !== false);

	$: tierCounts = {
		all: skills.length,
		standard: skills.filter((s) => !s.tier || s.tier === 'standard').length,
		store: skills.filter((s) => s.tier === 'store').length,
		required: skills.filter((s) => s.tier === 'required' || s.user_toggleable === false).length
	};

	$: filteredSkills = skills.filter((skill) => {
		if (activeTier === 'all') return true;
		if (activeTier === 'standard') return !skill.tier || skill.tier === 'standard';
		if (activeTier === 'store') return skill.tier === 'store';
		if (activeTier === 'required')
			return skill.tier === 'required' || skill.user_toggleable === false;
		return true;
	});

	$: hasTierTabs = tierCounts.standard > 0 && (tierCounts.store > 0 || tierCounts.required > 0);

	function isSkillToggleable(skill: SkillItem) {
		return skill.user_toggleable !== false && skill.tier !== 'required';
	}

	function isSkillRequired(skill: SkillItem) {
		return skill.tier === 'required' || skill.user_toggleable === false;
	}

	function isStoreSkill(skill: SkillItem) {
		return skill.tier === 'store';
	}
</script>

<h3>Skills</h3>
<div class="skills-header">
	<p>Manage installed skills and permissions here.</p>
	<Tooltip disabled={!tooltipsEnabled}>
		<TooltipTrigger>
			{#snippet child({ props })}
				{@const { type: _type, ...restProps } = props}
				<label class="skill-toggle" {...restProps}>
					<input
						type="checkbox"
						checked={allSkillsEnabled}
						disabled={!hasToggleableSkills}
						onchange={(event) => toggleAllSkills((event.currentTarget as HTMLInputElement).checked)}
					/>
					<span class="skill-switch" aria-hidden="true"></span>
					<span class="skill-toggle-label">Enable all</span>
				</label>
			{/snippet}
		</TooltipTrigger>
		<TooltipContent side="top">{TOOLTIP_COPY.enableAllSkills}</TooltipContent>
	</Tooltip>
</div>

{#if hasTierTabs}
	<div class="tier-tabs">
		{#each [['all', 'All'], ['standard', 'Standard'], ['store', 'Store'], ['required', 'Required']] as [key, label]}
			{@const count = tierCounts[key as TierFilter]}
			{#if key === 'all' || count > 0}
				<button
					class="tier-tab"
					class:active={activeTier === key}
					onclick={() => (activeTier = key as TierFilter)}
				>
					{label}
					{#if count > 0}
						<span class="tier-tab-count">{count}</span>
					{/if}
				</button>
			{/if}
		{/each}
	</div>
{/if}

<div class="skills-panel">
	{#if isLoadingSkills}
		<div class="settings-meta">
			<LoadingGlyph size={LOADING_SIZES.inline} />
			Loading skills...
		</div>
	{:else if skillsError}
		<div class="settings-error">{skillsError}</div>
	{:else if skills.length === 0}
		<div class="settings-meta">No skills found.</div>
	{:else if filteredSkills.length === 0}
		<div class="settings-meta">No skills in this category.</div>
	{:else}
		{#each groupSkills(filteredSkills) as [category, categorySkills]}
			<div class="skills-category">
				<div class="skills-category-title">{category}</div>
				<div class="skills-grid">
					{#each categorySkills as skill}
						{@const toggleable = isSkillToggleable(skill)}
						{@const required = isSkillRequired(skill)}
						{@const isStore = isStoreSkill(skill)}
						<div class="skill-row" class:skill-row-required={required}>
							<div class="skill-row-header">
								<div class="skill-name">
									{skill.name}
									{#if required}
										<span class="skill-tier-badge skill-tier-required">Required</span>
									{:else if isStore}
										<span class="skill-tier-badge skill-tier-store">Store</span>
									{/if}
								</div>
								<div class="skill-row-controls">
									{#if isStore && enabledSkills.includes(skill.id) && onOpenDetail}
										<button
											class="skill-configure-btn"
											onclick={() => onOpenDetail && onOpenDetail(skill)}
										>
											Configure
										</button>
									{/if}
									<Tooltip disabled={!tooltipsEnabled}>
										<TooltipTrigger>
											{#snippet child({ props })}
												{@const { type: _type, ...restProps } = props}
												<label class="skill-toggle" {...restProps}>
													<input
														type="checkbox"
														checked={enabledSkills.includes(skill.id) || required}
														disabled={!toggleable}
														onchange={(event) =>
															toggleable &&
															toggleSkill(
																skill.id,
																(event.currentTarget as HTMLInputElement).checked
															)}
													/>
													<span class="skill-switch" aria-hidden="true"></span>
												</label>
											{/snippet}
										</TooltipTrigger>
										<TooltipContent side="top">
											{#if required}
												{skill.name} cannot be disabled
											{:else if toggleable}
												{enabledSkills.includes(skill.id) ? 'Disable' : 'Enable'}
												{skill.name}
											{:else}
												{skill.name} cannot be disabled
											{/if}
										</TooltipContent>
									</Tooltip>
								</div>
							</div>
							<div class="skill-description">{skill.description}</div>
						</div>
					{/each}
				</div>
			</div>
		{/each}
	{/if}
</div>

<style>
	h3 {
		margin: 0 0 0.5rem;
	}

	.skills-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		color: var(--color-muted-foreground);
		font-size: 0.85rem;
		margin-bottom: 1rem;
	}

	.skills-header p {
		margin: 0;
	}

	.tier-tabs {
		display: flex;
		gap: 0.35rem;
		margin-bottom: 1rem;
		flex-wrap: wrap;
	}

	.tier-tab {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.3rem 0.7rem;
		border-radius: 999px;
		border: 1px solid var(--color-border);
		background: transparent;
		color: var(--color-muted-foreground);
		font-size: 0.75rem;
		cursor: pointer;
		transition:
			background 0.15s,
			color 0.15s;
	}

	.tier-tab:hover,
	.tier-tab.active {
		background: var(--color-sidebar-accent);
		color: var(--color-foreground);
		border-color: var(--color-foreground);
	}

	.tier-tab-count {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 1.1rem;
		height: 1.1rem;
		border-radius: 999px;
		background: var(--color-border);
		font-size: 0.65rem;
		font-weight: 600;
		padding: 0 0.25rem;
	}

	.skills-panel {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.skills-category {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.skills-category-title {
		font-size: 0.72rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
	}

	.skills-grid {
		display: grid;
		gap: 0.75rem;
		grid-template-columns: repeat(3, minmax(0, 1fr));
	}

	@media (max-width: 1200px) {
		.skills-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 820px) {
		.skills-grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	.skill-row {
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		padding: 0.75rem 0.85rem;
		background: var(--color-sidebar-accent);
	}

	.skill-row-required {
		opacity: 0.7;
	}

	.skill-row-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	.skill-name {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		flex-wrap: wrap;
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.skill-tier-badge {
		display: inline-block;
		padding: 0.1rem 0.4rem;
		border-radius: 999px;
		font-size: 0.65rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		border: 1px solid var(--color-border);
	}

	.skill-tier-required {
		background: color-mix(in oklab, var(--color-muted-foreground) 10%, transparent);
		color: var(--color-muted-foreground);
	}

	.skill-tier-store {
		background: color-mix(in oklab, var(--color-primary) 15%, transparent);
		color: var(--color-primary);
		border-color: color-mix(in oklab, var(--color-primary) 30%, transparent);
	}

	.skill-row-controls {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		flex-shrink: 0;
	}

	.skill-configure-btn {
		display: inline-flex;
		align-items: center;
		padding: 0.2rem 0.55rem;
		border-radius: 999px;
		border: 1px solid var(--color-border);
		background: transparent;
		color: var(--color-muted-foreground);
		font-size: 0.72rem;
		cursor: pointer;
		transition: background 0.15s;
	}

	.skill-configure-btn:hover {
		background: var(--color-card);
		color: var(--color-foreground);
	}

	.skill-description {
		margin-top: 0.35rem;
		font-size: 0.8rem;
		line-height: 1.4;
		color: var(--color-muted-foreground);
	}

	.skill-toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		cursor: pointer;
		user-select: none;
	}

	.skill-toggle input {
		position: absolute;
		opacity: 0;
		width: 1px;
		height: 1px;
	}

	.skill-switch {
		width: 36px;
		height: 20px;
		border-radius: 999px;
		background: var(--color-border);
		position: relative;
		transition: background 0.2s ease;
	}

	.skill-switch::after {
		content: '';
		position: absolute;
		top: 2px;
		left: 2px;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: var(--color-background);
		transition: transform 0.2s ease;
	}

	.skill-toggle input:checked + .skill-switch {
		background: var(--color-primary);
	}

	.skill-toggle input:checked + .skill-switch::after {
		transform: translateX(16px);
	}

	.skill-toggle input:focus-visible + .skill-switch {
		outline: 2px solid var(--color-ring);
		outline-offset: 2px;
	}

	.skill-toggle input:disabled + .skill-switch {
		opacity: 0.55;
	}

	.skill-toggle-label {
		font-size: 0.8rem;
		color: var(--color-foreground);
	}
</style>
