<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { onDestroy, onMount } from 'svelte';
	import { applyThemeMode, getStoredTheme, setThemeMode } from '$lib/utils/theme';
	import { canShowTooltips } from '$lib/utils/tooltip';

	let isDark = $state(false);
	let cleanupThemeListener: (() => void) | null = null;
	let tooltipsEnabled = $state(false);

	onMount(() => {
		if (typeof window === 'undefined') {
			return;
		}
		const stored = getStoredTheme();
		isDark =
			stored === 'dark' ||
			(!stored && window.matchMedia('(prefers-color-scheme: dark)').matches);

		applyThemeMode(isDark ? 'dark' : 'light', false);

		const handler = (event: Event) => {
			const detail = (event as CustomEvent<{ theme?: string; source?: string }>).detail;
			if (detail?.theme === 'dark') {
				isDark = true;
			} else if (detail?.theme === 'light') {
				isDark = false;
			}
		};
		window.addEventListener('themechange', handler);
		cleanupThemeListener = () => window.removeEventListener('themechange', handler);
		tooltipsEnabled = canShowTooltips();
	});

	onDestroy(() => {
		if (cleanupThemeListener) {
			cleanupThemeListener();
		}
	});

	function toggleTheme() {
		isDark = !isDark;
		setThemeMode(isDark ? 'dark' : 'light', 'user');
	}
</script>

<Tooltip disabled={!tooltipsEnabled}>
	<TooltipTrigger>
		{#snippet child({ props })}
			<Button
				variant="outline"
				size="icon"
				onclick={toggleTheme}
				aria-label="Toggle theme"
				class="border-border"
				{...props}
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
		{/snippet}
	</TooltipTrigger>
	<TooltipContent side="bottom">Toggle dark/light mode</TooltipContent>
</Tooltip>
