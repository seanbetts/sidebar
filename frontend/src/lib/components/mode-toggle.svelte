<script lang="ts">
	import { invokeSnippetClick } from '$lib/utils/svelteEvents';
	import { Button } from '$lib/components/ui/button';
	import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
	import { onDestroy, onMount } from 'svelte';
	import {
		applyThemeMode,
		getStoredTheme,
		getSystemTheme,
		setThemeMode,
		startSystemThemeSync,
		type ResolvedThemeMode,
		type ThemeMode
	} from '$lib/utils/theme';
	import { canShowTooltips } from '$lib/utils/tooltip';

	let resolvedTheme = $state<ResolvedThemeMode>('light');
	let cleanupThemeListener: (() => void) | null = null;
	let cleanupSystemThemeSync: (() => void) | null = null;
	let tooltipsEnabled = $state(false);

	onMount(() => {
		if (typeof window === 'undefined') {
			return;
		}
		const stored = getStoredTheme();
		applyThemeMode(stored ?? getSystemTheme(), false);
		resolvedTheme = document.documentElement.classList.contains('dark') ? 'dark' : 'light';

		const handler = (event: Event) => {
			const detail = (
				event as CustomEvent<{
					resolvedTheme?: ResolvedThemeMode;
					source?: string;
				}>
			).detail;
			if (detail?.resolvedTheme === 'light' || detail?.resolvedTheme === 'dark') {
				resolvedTheme = detail.resolvedTheme;
			}
		};
		window.addEventListener('themechange', handler);
		cleanupThemeListener = () => window.removeEventListener('themechange', handler);
		cleanupSystemThemeSync = startSystemThemeSync();
		tooltipsEnabled = canShowTooltips();
	});

	onDestroy(() => {
		if (cleanupThemeListener) {
			cleanupThemeListener();
		}
		if (cleanupSystemThemeSync) {
			cleanupSystemThemeSync();
		}
	});

	function toggleTheme() {
		setThemeMode(resolvedTheme === 'dark' ? 'light' : 'dark', 'user');
	}
</script>

<Tooltip disabled={!tooltipsEnabled}>
	<TooltipTrigger>
		{#snippet child({ props })}
			<Button
				variant="outline"
				size="icon"
				{...props}
				onclick={(event) => {
					invokeSnippetClick(props, event);
					toggleTheme();
				}}
				aria-label={resolvedTheme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
				class="border-border"
			>
				{#if resolvedTheme === 'dark'}
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
	<TooltipContent side="bottom">
		{resolvedTheme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode'}
	</TooltipContent>
</Tooltip>
