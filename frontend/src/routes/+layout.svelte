<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/history/Sidebar.svelte';
	import SiteHeader from '$lib/components/site-header.svelte';
	import { Toaster } from 'svelte-sonner';
</script>

<svelte:head>
	<title>sideBar</title>
</svelte:head>

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
