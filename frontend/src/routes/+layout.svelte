<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/left-sidebar/Sidebar.svelte';
	import SiteHeader from '$lib/components/site-header.svelte';
	import HoldingPage from '$lib/components/HoldingPage.svelte';
	import { Toaster } from 'svelte-sonner';
	import { initAuth } from '$lib/stores/auth';
	import { onDestroy, onMount } from 'svelte';
	import { toast } from 'svelte-sonner';
	import { chatStore } from '$lib/stores/chat';
	import { get } from 'svelte/store';
	import { clearCaches, clearInFlight, clearMemoryCache, listenForStorageEvents } from '$lib/utils/cache';

	let { data } = $props();
	let healthChecked = false;
	let stopStorageListener: (() => void) | null = null;

	onMount(() => {
		initAuth(
			data.session,
			data.user,
			data.supabaseUrl,
			data.supabaseAnonKey
		);
		stopStorageListener = listenForStorageEvents();
		if (!data.session) {
			clearCaches();
			clearMemoryCache();
			clearInFlight();
			return;
		}
		checkHealth();
		restoreLastConversation();
	});

	onDestroy(() => {
		stopStorageListener?.();
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
			console.error('Health check failed:', error);
			toast.error('Some services are unavailable. Restart the backend via Doppler and refresh.');
		}
	}

	async function restoreLastConversation() {
		const state = get(chatStore);
		if (state.conversationId) return;
		const lastConversationId = chatStore.getLastConversationId();
		if (!lastConversationId) return;
		try {
			await chatStore.loadConversation(lastConversationId);
		} catch (error) {
			console.warn('Failed to restore last conversation:', error);
			chatStore.clearLastConversation();
		}
	}
</script>

<svelte:head>
	<title>sideBar</title>
</svelte:head>

{#if data.maintenanceMode}
	<HoldingPage />
{:else if !data.session}
	<slot />
{:else}
	<div class="app" data-sveltekit-preload-code="tap" data-sveltekit-preload-data="tap">
		<Sidebar />
		<main class="main-content">
			<SiteHeader />
			<div class="page-content">
				<slot />
			</div>
		</main>
	</div>

	<Toaster richColors position="top-right" />
{/if}

<style>
	.app {
		display: flex;
		height: 100vh;
		width: 100vw;
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
		overflow: hidden;
	}

	:global(.page-content > *) {
		flex: 1;
		min-height: 0;
	}
</style>
