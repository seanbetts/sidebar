<script lang="ts">
	import { X } from 'lucide-svelte';
	import { browser } from '$app/environment';

	export let onSearch: ((query: string) => void | Promise<void>) | undefined = undefined;
	export let onClear: (() => void | Promise<void>) | undefined = undefined;
	export let placeholder: string = 'Type to search...';

	let searchQuery = '';
	let debounceTimeout: ReturnType<typeof setTimeout>;
	let previousQuery = '';

	function handleSearch() {
		if (!browser) {
			return;
		}
		clearTimeout(debounceTimeout);
		debounceTimeout = setTimeout(async () => {
			// Skip if query hasn't actually changed
			if (searchQuery === previousQuery) {
				return;
			}
			previousQuery = searchQuery;

			if (onSearch) {
				await onSearch(searchQuery);
			}
		}, 300); // 300ms debounce
	}

	function clearSearch() {
		if (!browser) {
			searchQuery = '';
			return;
		}
		searchQuery = '';
		previousQuery = '';
		if (onClear) {
			onClear();
		}
	}

	// Only trigger search when query actually changes from previous value
	$: if (searchQuery !== previousQuery && onSearch) handleSearch();
</script>

<div class="search-bar">
	<div class="search-input-wrapper">
		<input type="text" bind:value={searchQuery} {placeholder} class="search-input" />
		{#if searchQuery}
			<button on:click={clearSearch} class="clear-btn" aria-label="Clear search">
				<X size={16} />
			</button>
		{/if}
	</div>
</div>

<style>
	.search-input-wrapper {
		position: relative;
		display: flex;
		align-items: center;
	}

	.search-input {
		width: 100%;
		padding: 0.5rem 0.75rem;
		border: 1px solid var(--color-sidebar-border);
		border-radius: 0.375rem;
		font-size: 0.875rem;
		background-color: var(--color-sidebar-accent);
		color: var(--color-sidebar-foreground);
		transition: border-color 0.2s;
	}

	.search-input::placeholder {
		color: var(--color-muted-foreground);
		opacity: 0.7;
	}

	.search-input:focus {
		outline: none;
		border-color: var(--color-sidebar-primary);
	}

	.clear-btn {
		position: absolute;
		right: 0.5rem;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 0.25rem;
		background: none;
		border: none;
		cursor: pointer;
		border-radius: 0.25rem;
		color: var(--color-muted-foreground);
		transition: background-color 0.2s;
	}

	.clear-btn:hover {
		background-color: var(--color-accent);
	}
</style>
