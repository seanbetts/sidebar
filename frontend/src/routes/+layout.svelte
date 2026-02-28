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
	import { flushClientSessionOnLogout } from '$lib/utils/sessionCleanup';
	import { listenForStorageEvents } from '$lib/utils/cache';
	import { applyThemeMode, getStoredTheme } from '$lib/utils/theme';
	import { startRealtime, stopRealtime } from '$lib/realtime/realtime';
	import { startTaskEvents, stopTaskEvents } from '$lib/realtime/task_events';
	import { logError } from '$lib/utils/errorHandling';
	import { initWebVitals } from '$lib/utils/performance';
	import {
		SIDEBAR_SWIPE_CONFIG,
		resolveSidebarSwipeAction,
		supportsSidebarSwipeGestures
	} from '$lib/utils/sidebarSwipe';

	let { data, children } = $props();
	let healthChecked = false;
	let stopStorageListener: (() => void) | null = null;
	let stopRealtimeListener: (() => void) | null = null;
	let stopDebugListener: (() => void) | null = null;
	let stopSwipeViewportListener: (() => void) | null = null;

	let debugLayout = $state(false);
	let viewportDebug = $state('');
	let isSidebarCollapsed = $state(false);
	let sidebarSwipeEnabled = $state(false);
	let pageContentRef = $state<HTMLElement | null>(null);

	interface SwipeStartSnapshot {
		startX: number;
		startY: number;
		startedAtMs: number;
		startedNearLeadingEdge: boolean;
	}

	interface TouchPointLike {
		clientX: number;
		clientY: number;
	}

	interface WorkspaceTouchEventLike extends Event {
		touches: ArrayLike<TouchPointLike>;
		changedTouches: ArrayLike<TouchPointLike>;
	}

	let swipeStartSnapshot = $state<SwipeStartSnapshot | null>(null);

	onMount(() => {
		debugLayout =
			typeof window !== 'undefined' &&
			new URL(window.location.href).searchParams.has('debugLayout');
		if (debugLayout) {
			const update = () => {
				const appHeightVar =
					getComputedStyle(document.documentElement).getPropertyValue('--app-height')?.trim() ?? '';
				const vvHeight = window.visualViewport?.height;
				viewportDebug = [
					`innerHeight=${window.innerHeight}`,
					`clientHeight=${document.documentElement.clientHeight}`,
					`visualViewport.height=${vvHeight ?? 'n/a'}`,
					`--app-height=${appHeightVar || 'unset'}`
				].join(' | ');
			};
			update();
			window.addEventListener('resize', update);
			window.visualViewport?.addEventListener('resize', update);
			stopDebugListener = () => {
				window.removeEventListener('resize', update);
				window.visualViewport?.removeEventListener('resize', update);
			};
		}

		const updateSidebarSwipeEnabled = () => {
			sidebarSwipeEnabled = supportsSidebarSwipeGestures(
				window.innerWidth,
				navigator.maxTouchPoints ?? 0
			);
		};
		updateSidebarSwipeEnabled();
		window.addEventListener('resize', updateSidebarSwipeEnabled);
		stopSwipeViewportListener = () => {
			window.removeEventListener('resize', updateSidebarSwipeEnabled);
		};

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
				startTaskEvents(currentUser.id);
			} else {
				stopRealtime();
				stopTaskEvents();
			}
		});
		stopStorageListener = listenForStorageEvents();
		if (!data.isAuthenticated) {
			void flushClientSessionOnLogout().catch((error) => {
				logError('Session cleanup failed on signed-out layout', error, {
					scope: 'layout.clearSessionCleanup'
				});
			});
			return;
		}
		checkHealth();
		chatStore.reset();
	});

	onDestroy(() => {
		stopStorageListener?.();
		stopRealtimeListener?.();
		stopDebugListener?.();
		stopSwipeViewportListener?.();
		stopRealtime();
		stopTaskEvents();
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

	function clearSwipeStart() {
		swipeStartSnapshot = null;
	}

	function handleWorkspaceTouchStart(event: Event) {
		const touchEvent = event as WorkspaceTouchEventLike;
		if (!sidebarSwipeEnabled || !pageContentRef || touchEvent.touches.length !== 1) {
			clearSwipeStart();
			return;
		}

		const touch = touchEvent.touches[0];
		const pageLeft = pageContentRef.getBoundingClientRect().left;
		swipeStartSnapshot = {
			startX: touch.clientX,
			startY: touch.clientY,
			startedAtMs: Date.now(),
			startedNearLeadingEdge: touch.clientX - pageLeft <= SIDEBAR_SWIPE_CONFIG.edgeActivationPx
		};
	}

	function handleWorkspaceTouchEnd(event: Event) {
		const touchEvent = event as WorkspaceTouchEventLike;
		if (!sidebarSwipeEnabled || !swipeStartSnapshot || touchEvent.changedTouches.length !== 1) {
			clearSwipeStart();
			return;
		}

		const touch = touchEvent.changedTouches[0];
		const action = resolveSidebarSwipeAction({
			startX: swipeStartSnapshot.startX,
			endX: touch.clientX,
			startY: swipeStartSnapshot.startY,
			endY: touch.clientY,
			durationMs: Date.now() - swipeStartSnapshot.startedAtMs,
			startedNearLeadingEdge: swipeStartSnapshot.startedNearLeadingEdge,
			isSidebarCollapsed
		});

		if (action === 'collapse') {
			isSidebarCollapsed = true;
		} else if (action === 'expand') {
			isSidebarCollapsed = false;
		}
		clearSwipeStart();
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
			<Sidebar bind:isCollapsed={isSidebarCollapsed} />
			<main class="main-content">
				<SiteHeader />
				<div
					class="page-content"
					bind:this={pageContentRef}
					ontouchstart={handleWorkspaceTouchStart}
					ontouchend={handleWorkspaceTouchEnd}
					ontouchcancel={clearSwipeStart}
				>
					{@render children()}
				</div>
			</main>
		</div>

		<Toaster richColors position="top-right" />
	</TooltipProvider>
{/if}

{#if debugLayout}
	<div class="debug-layout">{viewportDebug}</div>
{/if}

<style>
	.app {
		display: flex;
		height: var(--app-height, 100vh);
		height: var(--app-height, 100dvh); /* Prefer dvh when available */
		width: 100%;
		overflow: hidden;
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
		overflow: auto;
		overscroll-behavior: contain;
	}

	:global(.page-content > *) {
		flex: 1;
		min-height: 0;
		height: 100%;
	}

	.debug-layout {
		position: fixed;
		left: 12px;
		right: 12px;
		bottom: 12px;
		z-index: 99999;
		font-family:
			ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New',
			monospace;
		font-size: 12px;
		line-height: 1.3;
		padding: 10px 12px;
		border-radius: 10px;
		background: rgba(0, 0, 0, 0.75);
		color: white;
		backdrop-filter: blur(8px);
		pointer-events: none;
	}
</style>
