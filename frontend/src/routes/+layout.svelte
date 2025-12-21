<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/history/Sidebar.svelte';
</script>

<div class="app">
	<Sidebar />
	<main class="main-content">
		<slot />
	</main>
</div>

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
