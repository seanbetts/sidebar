<script lang="ts">
	import { Search } from 'lucide-svelte';
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
	import { LOADING_SIZES } from '$lib/components/loading/loadingSizes';
	import SkillDetailModal from '$lib/components/left-sidebar/panels/settings/SkillDetailModal.svelte';
	import type { SkillItem } from '$lib/types/skills';

	export let skills: SkillItem[] = [];
	export let enabledSkills: string[] = [];
	export let isLoadingSkills = false;
	export let skillsError = '';
	export let onInstall: (skill: SkillItem, providerKeys?: Record<string, string>) => Promise<void>;
	export let onUninstall: (skill: SkillItem) => Promise<void>;

	let searchQuery = '';
	let activeCategory = 'all';
	let selectedSkill: SkillItem | null = null;
	let detailOpen = false;
	let isInstalling = false;
	let installError = '';

	$: storeSkills = skills.filter((s) => s.tier === 'store' || s.installable === true);

	$: categories = ['all', ...new Set(storeSkills.map((s) => s.category || 'Other'))];

	$: filteredSkills = storeSkills.filter((skill) => {
		const matchesCategory =
			activeCategory === 'all' || (skill.category || 'Other') === activeCategory;
		const q = searchQuery.toLowerCase().trim();
		const matchesSearch =
			!q || skill.name.toLowerCase().includes(q) || skill.description.toLowerCase().includes(q);
		return matchesCategory && matchesSearch;
	});

	function openDetail(skill: SkillItem) {
		selectedSkill = skill;
		detailOpen = true;
		installError = '';
	}

	function closeDetail() {
		detailOpen = false;
		selectedSkill = null;
		installError = '';
	}

	async function handleInstall(skill: SkillItem) {
		isInstalling = true;
		installError = '';
		try {
			await onInstall(skill);
			closeDetail();
		} catch (err) {
			installError = err instanceof Error ? err.message : 'Failed to install skill';
		} finally {
			isInstalling = false;
		}
	}

	async function handleUninstall(skill: SkillItem) {
		isInstalling = true;
		installError = '';
		try {
			await onUninstall(skill);
			closeDetail();
		} catch (err) {
			installError = err instanceof Error ? err.message : 'Failed to uninstall skill';
		} finally {
			isInstalling = false;
		}
	}
</script>

<h3>Skills Store</h3>
<p class="store-subtitle">Browse and install skills to extend your assistant's capabilities.</p>

<div class="store-search-row">
	<div class="store-search-wrap">
		<Search size={14} class="store-search-icon" />
		<input
			class="store-search-input"
			type="search"
			placeholder="Search skills…"
			bind:value={searchQuery}
		/>
	</div>
</div>

{#if categories.length > 2}
	<div class="store-categories">
		{#each categories as cat}
			<button
				class="store-cat-chip"
				class:active={activeCategory === cat}
				onclick={() => (activeCategory = cat)}
			>
				{cat === 'all' ? 'All' : cat}
			</button>
		{/each}
	</div>
{/if}

{#if isLoadingSkills}
	<div class="settings-meta">
		<LoadingGlyph size={LOADING_SIZES.inline} />
		Loading…
	</div>
{:else if skillsError}
	<div class="settings-error">{skillsError}</div>
{:else if storeSkills.length === 0}
	<div class="settings-meta">No store skills available.</div>
{:else if filteredSkills.length === 0}
	<div class="settings-meta">No skills match your search.</div>
{:else}
	<div class="store-grid">
		{#each filteredSkills as skill (skill.id)}
			{@const installed = enabledSkills.includes(skill.id)}
			<button class="store-card" onclick={() => openDetail(skill)}>
				<div class="store-card-header">
					<div class="store-card-name">{skill.name}</div>
					<div class="store-card-pill" class:installed>
						{installed ? 'Installed' : 'Install'}
					</div>
				</div>
				<div class="store-card-desc">{skill.description}</div>
				{#if skill.category}
					<div class="store-card-category">{skill.category}</div>
				{/if}
			</button>
		{/each}
	</div>
{/if}

<SkillDetailModal
	bind:open={detailOpen}
	skill={selectedSkill}
	{enabledSkills}
	{isInstalling}
	{installError}
	onInstall={handleInstall}
	onUninstall={handleUninstall}
	onClose={closeDetail}
/>

<style>
	h3 {
		margin: 0 0 0.25rem;
	}

	.store-subtitle {
		margin: 0 0 1rem;
		font-size: 0.85rem;
		color: var(--color-muted-foreground);
	}

	.store-search-row {
		margin-bottom: 0.75rem;
	}

	.store-search-wrap {
		position: relative;
		display: flex;
		align-items: center;
	}

	:global(.store-search-icon) {
		position: absolute;
		left: 0.65rem;
		color: var(--color-muted-foreground);
		pointer-events: none;
	}

	.store-search-input {
		width: 100%;
		padding: 0.55rem 0.75rem 0.55rem 2.1rem;
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: var(--color-card);
		color: var(--color-foreground);
		font-size: 0.85rem;
	}

	.store-search-input:focus {
		outline: none;
		border-color: var(--color-ring);
	}

	.store-categories {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
		margin-bottom: 1rem;
	}

	.store-cat-chip {
		display: inline-flex;
		align-items: center;
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

	.store-cat-chip:hover,
	.store-cat-chip.active {
		background: var(--color-sidebar-accent);
		color: var(--color-foreground);
		border-color: var(--color-foreground);
	}

	.store-grid {
		display: grid;
		gap: 0.75rem;
		grid-template-columns: repeat(3, minmax(0, 1fr));
	}

	@media (max-width: 1200px) {
		.store-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 820px) {
		.store-grid {
			grid-template-columns: minmax(0, 1fr);
		}
	}

	.store-card {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
		padding: 0.75rem 0.85rem;
		border: 1px solid var(--color-border);
		border-radius: 0.75rem;
		background: var(--color-sidebar-accent);
		text-align: left;
		cursor: pointer;
		transition:
			border-color 0.15s,
			box-shadow 0.15s;
	}

	.store-card:hover {
		border-color: var(--color-foreground);
		box-shadow: 0 2px 8px color-mix(in oklab, var(--color-foreground) 8%, transparent);
	}

	.store-card-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.store-card-name {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-foreground);
	}

	.store-card-pill {
		display: inline-flex;
		align-items: center;
		padding: 0.15rem 0.55rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 600;
		border: 1px solid var(--color-border);
		background: transparent;
		color: var(--color-muted-foreground);
		white-space: nowrap;
		flex-shrink: 0;
	}

	.store-card-pill.installed {
		background: color-mix(in oklab, var(--color-primary) 15%, transparent);
		color: var(--color-primary);
		border-color: color-mix(in oklab, var(--color-primary) 30%, transparent);
	}

	.store-card-desc {
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
		line-height: 1.4;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}

	.store-card-category {
		font-size: 0.7rem;
		color: var(--color-muted-foreground);
		text-transform: uppercase;
		letter-spacing: 0.05em;
		margin-top: 0.15rem;
	}
</style>
