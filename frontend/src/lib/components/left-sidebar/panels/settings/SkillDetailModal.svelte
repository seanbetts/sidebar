<script lang="ts">
	import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
	import SkillCredentialManager from '$lib/components/left-sidebar/panels/settings/SkillCredentialManager.svelte';
	import type { SkillItem } from '$lib/types/skills';

	export let open = false;
	export let skill: SkillItem | null = null;
	export let enabledSkills: string[] = [];
	export let isInstalling = false;
	export let installError = '';
	export let onInstall: (skill: SkillItem) => void;
	export let onUninstall: (skill: SkillItem) => void;
	export let onClose: () => void;

	$: isInstalled = skill ? enabledSkills.includes(skill.id) : false;
	$: requiredCredentials = skill?.credential_requirements?.filter((r) => r.required) ?? [];
	$: optionalCredentials = skill?.credential_requirements?.filter((r) => !r.required) ?? [];
	$: allCredentials = skill?.credential_requirements ?? [];

	function formatDate(value?: string): string {
		if (!value) return '';
		try {
			return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
		} catch {
			return value;
		}
	}
</script>

<AlertDialog.Root bind:open>
	<AlertDialog.Content class="skill-detail-dialog">
		{#if skill}
			<AlertDialog.Header>
				<AlertDialog.Title>{skill.name}</AlertDialog.Title>
				<AlertDialog.Description>{skill.description}</AlertDialog.Description>
			</AlertDialog.Header>

			<div class="skill-detail-body">
				<div class="skill-detail-meta">
					{#if skill.tier}
						<span class="skill-badge skill-badge-{skill.tier}">{skill.tier}</span>
					{/if}
					{#if skill.status && skill.status !== 'active'}
						<span class="skill-badge skill-badge-status">{skill.status}</span>
					{/if}
					{#if skill.version}
						<span class="skill-meta-item">v{skill.version}</span>
					{/if}
					{#if skill.updated_at}
						<span class="skill-meta-item">Updated {formatDate(skill.updated_at)}</span>
					{/if}
					{#if skill.install_count != null}
						<span class="skill-meta-item">{skill.install_count.toLocaleString()} installs</span>
					{/if}
				</div>

				{#if skill.long_description}
					<div class="skill-detail-section">
						<div class="skill-detail-section-title">Description</div>
						<p class="skill-detail-text">{skill.long_description}</p>
					</div>
				{/if}

				{#if skill.how_it_works}
					<div class="skill-detail-section">
						<div class="skill-detail-section-title">How it works</div>
						<p class="skill-detail-text">{skill.how_it_works}</p>
					</div>
				{/if}

				{#if skill.requirements}
					<div class="skill-detail-section">
						<div class="skill-detail-section-title">Requirements</div>
						<p class="skill-detail-text">{skill.requirements}</p>
					</div>
				{/if}

				{#if allCredentials.length > 0}
					<div class="skill-detail-section">
						<SkillCredentialManager credentialRequirements={allCredentials} />
					</div>
				{/if}

				{#if installError}
					<div class="skill-detail-error">{installError}</div>
				{/if}
			</div>

			<AlertDialog.Footer>
				<AlertDialog.Cancel onclick={onClose}>Close</AlertDialog.Cancel>
				{#if isInstalled}
					<button
						class="skill-action-btn skill-action-btn-uninstall"
						onclick={() => skill && onUninstall(skill)}
						disabled={isInstalling}
					>
						{isInstalling ? 'Uninstalling…' : 'Uninstall'}
					</button>
				{:else if skill.tier === 'store' || skill.installable}
					<button
						class="skill-action-btn skill-action-btn-install"
						onclick={() => skill && onInstall(skill)}
						disabled={isInstalling}
					>
						{isInstalling ? 'Installing…' : 'Install'}
					</button>
				{/if}
			</AlertDialog.Footer>
		{/if}
	</AlertDialog.Content>
</AlertDialog.Root>

<style>
	:global(.skill-detail-dialog) {
		max-width: 560px !important;
		width: min(96vw, 560px) !important;
	}

	.skill-detail-body {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		margin-top: 0.5rem;
		max-height: 50vh;
		overflow-y: auto;
		padding-right: 0.25rem;
	}

	.skill-detail-meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.4rem;
	}

	.skill-badge {
		display: inline-block;
		padding: 0.15rem 0.5rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		border: 1px solid var(--color-border);
		background: var(--color-secondary);
		color: var(--color-muted-foreground);
	}

	.skill-badge-store {
		background: color-mix(in oklab, var(--color-primary) 15%, transparent);
		color: var(--color-primary);
		border-color: color-mix(in oklab, var(--color-primary) 30%, transparent);
	}

	.skill-badge-required {
		background: color-mix(in oklab, var(--color-muted-foreground) 10%, transparent);
		color: var(--color-muted-foreground);
	}

	.skill-badge-status {
		background: color-mix(in oklab, #f59e0b 15%, transparent);
		color: #b45309;
		border-color: color-mix(in oklab, #f59e0b 30%, transparent);
	}

	.skill-meta-item {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.skill-meta-item + .skill-meta-item::before {
		content: '·';
		margin-right: 0.4rem;
	}

	.skill-detail-section {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.skill-detail-section-title {
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-muted-foreground);
	}

	.skill-detail-text {
		font-size: 0.85rem;
		color: var(--color-foreground);
		line-height: 1.5;
		margin: 0;
	}

	.skill-detail-error {
		font-size: 0.8rem;
		color: #d55b5b;
	}

	.skill-action-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		padding: 0.5rem 1.1rem;
		border-radius: 999px;
		border: none;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		transition: opacity 0.15s;
	}

	.skill-action-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.skill-action-btn-install {
		background: var(--color-primary);
		color: var(--color-primary-foreground);
	}

	.skill-action-btn-uninstall {
		background: var(--color-secondary);
		border: 1px solid var(--color-border);
		color: var(--color-foreground);
	}
</style>
