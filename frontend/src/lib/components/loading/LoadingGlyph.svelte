<script lang="ts">
	import { LOADING_SIZES } from './loadingSizes';

	export let size: number = LOADING_SIZES.panel;
	export let label: string = '';
	export let lightSrc: string = '/images/loading-light.gif';
	export let darkSrc: string = '/images/loading-dark.gif';

	$: trimmedLabel = label.trim();
</script>

<span
	class="loading-glyph"
	style={`--loading-size:${size}px;`}
	role={trimmedLabel ? 'img' : undefined}
	aria-label={trimmedLabel || undefined}
	aria-hidden={trimmedLabel ? undefined : 'true'}
>
	<img class="loading-image loading-image-light" src={lightSrc} alt="" />
	<img class="loading-image loading-image-dark" src={darkSrc} alt="" />
</span>

<style>
	.loading-glyph {
		width: var(--loading-size);
		height: var(--loading-size);
		display: inline-grid;
		place-items: center;
		line-height: 0;
		flex: 0 0 auto;
	}

	.loading-image {
		width: 100%;
		height: 100%;
		object-fit: contain;
	}

	.loading-image-dark {
		display: none;
	}

	:global(.dark) .loading-image-light {
		display: none;
	}

	:global(.dark) .loading-image-dark {
		display: block;
	}
</style>
