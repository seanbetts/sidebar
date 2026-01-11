<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/left-sidebar/Sidebar.svelte';
	import SiteHeader from '$lib/components/site-header.svelte';
	import HoldingPage from '$lib/components/HoldingPage.svelte';
	import { Toaster } from 'svelte-sonner';
	import { TooltipProvider } from '$lib/components/ui/tooltip';
	import { initAuth, user } from '$lib/stores/auth';
	import { onDestroy, onMount } from 'svelte';
	import { toast } from 'svelte-sonner';
	import { chatStore } from '$lib/stores/chat';
	import { get } from 'svelte/store';
	import { page } from '$app/stores';
	import {
		clearCaches,
		clearInFlight,
		clearMemoryCache,
		listenForStorageEvents
	} from '$lib/utils/cache';
	import { applyThemeMode, getStoredTheme } from '$lib/utils/theme';
	import { startRealtime, stopRealtime } from '$lib/realtime/realtime';
	import { logError } from '$lib/utils/errorHandling';
	import { initWebVitals } from '$lib/utils/performance';

	let { data, children } = $props();
	let healthChecked = false;
	let stopStorageListener: (() => void) | null = null;
	let stopRealtimeListener: (() => void) | null = null;

	onMount(() => {
		const storedTheme = getStoredTheme();
		const prefersDark =
			typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
		const initialTheme = storedTheme ?? (prefersDark ? 'dark' : 'light');
		applyThemeMode(initialTheme, false);
		void initWebVitals(() => get(page).url.pathname);

		const supabaseUrl = data.supabaseUrl;
		const supabaseAnonKey = data.supabaseAnonKey;
		if (!supabaseUrl || !supabaseAnonKey) {
			logError(
				'Missing Supabase config',
				new Error('SUPABASE_URL or SUPABASE_ANON_KEY is missing'),
				{
					scope: 'layout.initAuth'
				}
			);
			return;
		}
		initAuth(null, data.user, supabaseUrl, supabaseAnonKey);
		stopRealtimeListener = user.subscribe((currentUser) => {
			if (currentUser?.id) {
				void startRealtime(currentUser.id);
			} else {
				stopRealtime();
			}
		});
		stopStorageListener = listenForStorageEvents();
		if (!data.isAuthenticated) {
			clearCaches();
			clearMemoryCache();
			clearInFlight();
			return;
		}
		checkHealth();
		chatStore.reset();
	});

	onDestroy(() => {
		stopStorageListener?.();
		stopRealtimeListener?.();
		stopRealtime();
		chatStore.cleanup?.();
	});

	async function checkHealth() {
		if (healthChecked) return;
		healthChecked = true;
		try {
			const response = await fetch('/api/health');
			if (!response.ok) {
				toast.error('Some services are unavailable. Restart the backend via Doppler and refresh.');
				return;
			}
			const data = await response.json();
			if (data?.status && data.status !== 'healthy') {
				toast.error('Some services are unavailable. Restart the backend via Doppler and refresh.');
			}
		} catch (error) {
			logError('Health check failed', error, { scope: 'layout.checkHealth' });
			toast.error('Some services are unavailable. Restart the backend via Doppler and refresh.');
		}
	}
</script>

<svelte:head>
	<title>sideBar</title>
</svelte:head>

{#if data.maintenanceMode}
	<HoldingPage />
{:else if !data.isAuthenticated}
	{@render children()}
{:else}
	<TooltipProvider delayDuration={250}>
		<div class="app" data-sveltekit-preload-code="tap" data-sveltekit-preload-data="tap">
			<Sidebar />
			<main class="main-content">
				<SiteHeader />
				<div class="page-content">
					{@render children()}
				</div>
			</main>
		</div>

		<Toaster richColors position="top-right" />
	</TooltipProvider>
{/if}

<style>
	.app {
		display: flex;
		height: 100vh;
		height: 100dvh; /* Dynamic viewport height for mobile browsers */
		width: 100vw;
		overflow: hidden;
	}

	/* Safari-specific fix for older versions that don't support dvh */
	@supports (-webkit-touch-callout: none) {
		.app {
			height: -webkit-fill-available;
		}
	}

	.main-content {
		display: flex;
		flex-direction: column;
		flex: 1;
		height: 100%;
		min-height: 0;
		overflow: hidden;
	}

	.page-content {
		flex: 1;
		display: flex;
		min-height: 0;
		overflow: hidden;
	}

	:global(.page-content > *) {
		flex: 1;
		min-height: 0;
	}
</style>
