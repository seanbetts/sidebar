<script lang="ts">
	import LoadingGlyph from '$lib/components/loading/LoadingGlyph.svelte';
	import { LOADING_SIZES } from '$lib/components/loading/loadingSizes';

	export let message: string = 'Loading...';
	export let rows: number = 3;

	const rowClasses = ['short', 'medium', 'long'];
</script>

<div class="sidebar-loading" role="status" aria-live="polite">
	<div class="loading-header">
		<LoadingGlyph size={LOADING_SIZES.panel} />
		<span class="loading-text">{message}</span>
	</div>
	<div class="loading-rows" aria-hidden="true">
		{#each Array.from({ length: rows }) as _, i}
			<div class={`loading-row ${rowClasses[i % rowClasses.length]}`}></div>
		{/each}
	</div>
</div>

<style>
	.sidebar-loading {
		padding: 0.75rem 0.5rem;
		color: var(--color-muted-foreground);
		font-size: 0.8rem;
	}

	.loading-header {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.loading-rows {
		margin-top: 0.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.loading-row {
		height: 0.5rem;
		border-radius: 999px;
		background: color-mix(in srgb, var(--color-muted-foreground) 22%, transparent);
		opacity: 0.7;
	}

	.loading-row.short {
		width: 45%;
	}

	.loading-row.medium {
		width: 70%;
	}

	.loading-row.long {
		width: 85%;
	}
</style>
