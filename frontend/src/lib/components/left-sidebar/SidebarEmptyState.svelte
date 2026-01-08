<script lang="ts">
	import type { ComponentType } from 'svelte';

	export let icon: ComponentType | null = null;
	export let title: string = 'Nothing here yet';
	export let subtitle: string | null = null;
</script>

<div class="sidebar-empty" role="status" aria-live="polite">
	{#if icon}
		<div class="empty-icon" aria-hidden="true">
			<svelte:component this={icon} size={20} />
		</div>
	{/if}
	<div class="empty-text">
		<div class="empty-title">{title}</div>
		{#if subtitle}
			<div class="empty-subtitle">{subtitle}</div>
		{/if}
	</div>
</div>

<style>
	.sidebar-empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.5rem;
		text-align: center;
		padding: 1.5rem 1rem;
		color: var(--color-muted-foreground);
		min-height: 180px;
	}

	.empty-icon {
		width: 36px;
		height: 36px;
		display: grid;
		place-items: center;
		border-radius: 999px;
		background: color-mix(in srgb, var(--color-muted-foreground) 12%, transparent);
		color: var(--color-muted-foreground);
	}

	.empty-title {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-sidebar-foreground);
	}

	.empty-subtitle {
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}
</style>
