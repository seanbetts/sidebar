<script lang="ts">
	import type { ComponentType } from 'svelte';

	export let icon: ComponentType | null = null;
	export let title: string;
	export let subtitle: string | null = null;
</script>

<div class="sidebar-sparse" role="status" aria-live="polite">
	{#if icon}
		<div class="sparse-icon" aria-hidden="true">
			<svelte:component this={icon} size={16} />
		</div>
	{/if}
	<div class="sparse-copy">
		<div class="sparse-title">{title}</div>
		{#if subtitle}
			<div class="sparse-subtitle">{subtitle}</div>
		{/if}
	</div>
</div>

<style>
	.sidebar-sparse {
		display: flex;
		align-items: flex-start;
		gap: 0.625rem;
		padding: 0.5rem 0.25rem;
		color: var(--color-muted-foreground);
	}

	.sparse-icon {
		width: 1.75rem;
		height: 1.75rem;
		display: grid;
		place-items: center;
		border-radius: 999px;
		background: color-mix(in srgb, var(--color-muted-foreground) 12%, transparent);
		color: var(--color-muted-foreground);
		flex: 0 0 auto;
	}

	.sparse-copy {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 0;
	}

	.sparse-title {
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--color-sidebar-foreground);
	}

	.sparse-subtitle {
		font-size: 0.8rem;
		color: var(--color-muted-foreground);
	}
</style>
