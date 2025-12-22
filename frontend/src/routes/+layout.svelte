<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/history/Sidebar.svelte';
	import SiteHeader from '$lib/components/site-header.svelte';
	import { Toaster } from 'svelte-sonner';
</script>

<div class="app">
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
		overflow: auto;
	}

	.page-content {
		flex: 1;
		overflow: auto;
	}
</style>
