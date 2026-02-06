<script lang="ts">
	import { Globe } from 'lucide-svelte';

	export let faviconUrl: string | null | undefined = null;
	export let size = 16;

	let imageFailed = false;
	let lastUrl = '';

	$: safeUrl = (faviconUrl ?? '').trim();
	$: if (safeUrl !== lastUrl) {
		lastUrl = safeUrl;
		imageFailed = false;
	}
</script>

<span class="favicon" style={`width:${size}px;height:${size}px;`} aria-hidden="true">
	{#if safeUrl && !imageFailed}
		<img
			src={safeUrl}
			alt=""
			loading="lazy"
			decoding="async"
			onerror={() => {
				imageFailed = true;
			}}
		/>
	{:else}
		<Globe {size} />
	{/if}
</span>

<style>
	.favicon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.favicon img {
		width: 100%;
		height: 100%;
		object-fit: contain;
		border-radius: 3px;
	}
</style>
