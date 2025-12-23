<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import { onMount } from 'svelte';
	import { getStoredTheme, setThemeMode } from '$lib/utils/theme';

	let isDark = $state(false);

	onMount(() => {
		const stored = getStoredTheme();
		isDark =
			stored === 'dark' ||
			(!stored && window.matchMedia('(prefers-color-scheme: dark)').matches);

		setThemeMode(isDark ? 'dark' : 'light');
	});

	function toggleTheme() {
		isDark = !isDark;
		setThemeMode(isDark ? 'dark' : 'light');
	}
</script>

<Button
	variant="outline"
	size="icon"
	onclick={toggleTheme}
	aria-label="Toggle theme"
	class="border-border"
>
	{#if isDark}
		<svg
			xmlns="http://www.w3.org/2000/svg"
			width="20"
			height="20"
			viewBox="0 0 24 24"
			fill="none"
			stroke="currentColor"
			stroke-width="2"
			stroke-linecap="round"
			stroke-linejoin="round"
		>
			<circle cx="12" cy="12" r="4" />
			<path d="M12 2v2" />
			<path d="M12 20v2" />
			<path d="m4.93 4.93 1.41 1.41" />
			<path d="m17.66 17.66 1.41 1.41" />
			<path d="M2 12h2" />
			<path d="M20 12h2" />
			<path d="m6.34 17.66-1.41 1.41" />
			<path d="m19.07 4.93-1.41 1.41" />
		</svg>
	{:else}
		<svg
			xmlns="http://www.w3.org/2000/svg"
			width="20"
			height="20"
			viewBox="0 0 24 24"
			fill="none"
			stroke="currentColor"
			stroke-width="2"
			stroke-linecap="round"
			stroke-linejoin="round"
		>
			<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" />
		</svg>
	{/if}
</Button>
