<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/history/Sidebar.svelte';
	import { Toaster } from 'svelte-sonner';
</script>

<div class="app">
	<Sidebar />
	<main class="main-content">
		<slot />
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
		flex: 1;
		overflow: auto;
	}
</style>
