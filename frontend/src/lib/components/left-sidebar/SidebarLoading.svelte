<script lang="ts">
	export let message: string = 'Loading...';
	export let rows: number = 3;

	const rowClasses = ['short', 'medium', 'long'];
</script>

<div class="sidebar-loading" role="status" aria-live="polite">
	<div class="loading-header">
		<span class="loading-dot" aria-hidden="true"></span>
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

	.loading-dot {
		width: 6px;
		height: 6px;
		border-radius: 999px;
		background: var(--color-muted-foreground);
		animation: loading-pulse 1.2s ease-in-out infinite;
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
		background: linear-gradient(
			90deg,
			color-mix(in srgb, var(--color-muted-foreground) 20%, transparent),
			color-mix(in srgb, var(--color-muted-foreground) 45%, transparent),
			color-mix(in srgb, var(--color-muted-foreground) 20%, transparent)
		);
		background-size: 200% 100%;
		animation: loading-shimmer 1.6s ease-in-out infinite;
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

	@keyframes loading-pulse {
		0%,
		100% {
			opacity: 0.4;
		}
		50% {
			opacity: 1;
		}
	}

	@keyframes loading-shimmer {
		0% {
			background-position: 0% 50%;
		}
		100% {
			background-position: 200% 50%;
		}
	}
</style>
