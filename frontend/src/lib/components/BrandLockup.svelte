<script lang="ts">
	export let size: 'compact' | 'large' = 'compact';
	export let name = 'sideBar';
</script>

<div class:compact={size === 'compact'} class:large={size === 'large'} class="brand-lockup">
	<span class="brand-mark" aria-hidden="true">
		<img
			class="brand-asset brand-asset-light"
			src="/images/loading-light-128.gif"
			alt=""
			width="56"
			height="56"
		/>
		<img
			class="brand-asset brand-asset-dark"
			src="/images/loading-dark-128.gif"
			alt=""
			width="56"
			height="56"
		/>
	</span>
	<span class="brand-name">{name}</span>
</div>

<style>
	.brand-lockup {
		display: inline-flex;
		align-items: center;
		width: fit-content;
		color: var(--color-foreground);
	}

	.brand-mark {
		position: relative;
		display: inline-grid;
		place-items: center;
		flex: 0 0 auto;
	}

	.brand-asset {
		grid-area: 1 / 1;
		display: block;
		width: 100%;
		height: 100%;
	}

	.brand-asset-dark {
		display: none;
	}

	:global(.dark) .brand-asset-light {
		display: none;
	}

	:global(.dark) .brand-asset-dark {
		display: block;
	}

	.brand-name {
		font-weight: 650;
		letter-spacing: -0.04em;
		line-height: 0.92;
	}

	.compact {
		gap: 0.8rem;
	}

	.compact .brand-mark {
		width: 2.1rem;
		height: 2.1rem;
	}

	.compact .brand-name {
		font-size: 1.75rem;
	}

	.large {
		gap: 1rem;
	}

	.large .brand-mark {
		width: 3.25rem;
		height: 3.25rem;
	}

	.large .brand-name {
		font-size: clamp(2.5rem, 5vw, 3.75rem);
	}
</style>
