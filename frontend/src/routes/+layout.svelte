<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/left-sidebar/Sidebar.svelte';
	import SiteHeader from '$lib/components/site-header.svelte';
	import HoldingPage from '$lib/components/HoldingPage.svelte';
	import { Toaster } from 'svelte-sonner';
	import { initAuth } from '$lib/stores/auth';
	import { onMount } from 'svelte';

	let { data } = $props();

	onMount(() => {
		initAuth(
			data.session,
			data.user,
			data.supabaseUrl,
			data.supabaseAnonKey
		);
	});
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
