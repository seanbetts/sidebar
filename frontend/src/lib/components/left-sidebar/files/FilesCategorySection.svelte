<script lang="ts">
	import { ChevronDown, ChevronRight, Folder, FolderOpen } from 'lucide-svelte';
	import type { ComponentType } from 'svelte';
	import type { IngestionListItem } from '$lib/types/ingestion';
	import FilesListItem from '$lib/components/left-sidebar/files/FilesListItem.svelte';

	export let searchQuery = '';
	export let categoryOrder: string[] = [];
	export let categoryLabels: Record<string, string> = {};
	export let categorizedItems: Record<string, IngestionListItem[]> = {};
	export let hasReadyItems = false;
	export let hasSearchResults = false;
	export let expandedCategories: Set<string>;
	export let stripExtension: (name: string) => string;
	export let iconForCategory: (category: string | null | undefined) => ComponentType;

	export let onToggleCategory: (category: string) => void;
	export let onOpen: (item: IngestionListItem) => void;
	export let onToggleMenu: (event: MouseEvent, menuKey: string) => void;
	export let onRename: (item: IngestionListItem) => void;
	export let onPinToggle: (item: IngestionListItem) => void;
	export let onDownload: (item: IngestionListItem) => void;
	export let onDelete: (item: IngestionListItem, event?: MouseEvent) => void;
	export let openMenuKey: string | null = null;
</script>

<div class="files-block">
	{#if !searchQuery}
		<div class="files-block-title">Files</div>
	{/if}
	{#if searchQuery}
		{#each categoryOrder as category}
			{#if categorizedItems[category]?.length}
				<div class="files-block-subtitle">{categoryLabels[category] ?? 'Files'}</div>
				<div class="files-block-list">
					{#each categorizedItems[category] as item (item.file.id)}
						<FilesListItem
							{item}
							icon={iconForCategory(category)}
							menuKey={`files-${item.file.id}`}
							{openMenuKey}
							displayName={stripExtension(item.file.filename_original)}
							{onOpen}
							{onToggleMenu}
							{onRename}
							{onPinToggle}
							{onDownload}
							{onDelete}
						/>
					{/each}
				</div>
			{/if}
		{/each}
	{:else}
		{#each categoryOrder as category}
			{#if categorizedItems[category]?.length}
				<div class="tree-node">
					<div class="node-content">
						<button class="node-button expandable" onclick={() => onToggleCategory(category)}>
							<span class="chevron">
								{#if expandedCategories.has(category)}
									<ChevronDown size={16} />
								{:else}
									<ChevronRight size={16} />
								{/if}
							</span>
							<span class="icon">
								{#if expandedCategories.has(category)}
									<FolderOpen size={16} />
								{:else}
									<Folder size={16} />
								{/if}
							</span>
							<span class="name">{categoryLabels[category] ?? 'Files'}</span>
						</button>
					</div>
				</div>
				{#if expandedCategories.has(category)}
					{#each categorizedItems[category] as item (item.file.id)}
						<FilesListItem
							{item}
							icon={iconForCategory(category)}
							menuKey={`files-${item.file.id}`}
							{openMenuKey}
							displayName={stripExtension(item.file.filename_original)}
							nested={true}
							{onOpen}
							{onToggleMenu}
							{onRename}
							{onPinToggle}
							{onDownload}
							{onDelete}
						/>
					{/each}
				{/if}
			{/if}
		{/each}
	{/if}
	{#if searchQuery && !hasSearchResults}
		<div class="files-empty">No matching files</div>
	{:else if !searchQuery && !hasReadyItems}
		<div class="files-empty">No files yet</div>
	{/if}
</div>

<style>
	.files-block {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.files-block-list {
		display: flex;
		flex-direction: column;
	}

	.files-block-title {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
		padding: 0 0.25rem;
	}

	.files-block-subtitle {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
		padding: 0.35rem 0.25rem 0.15rem;
	}

	.files-empty {
		padding: 0.5rem 0.25rem;
		color: var(--color-muted-foreground);
		font-size: 0.8rem;
	}

	.tree-node {
		user-select: none;
	}

	.node-content {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.node-button {
		display: flex;
		align-items: center;
		gap: 0.375rem;
		flex: 1;
		padding: 0.375rem 0.5rem;
		background: none;
		border: none;
		cursor: pointer;
		font-size: 0.85rem;
		color: var(--color-sidebar-foreground);
		transition: background-color 0.2s;
		text-align: left;
		min-width: 0;
	}

	.node-content:hover .node-button {
		background-color: var(--color-sidebar-accent);
	}

	.node-button.expandable {
		cursor: pointer;
	}

	.chevron {
		display: flex;
		align-items: center;
		color: var(--color-muted-foreground);
	}

	.icon {
		display: flex;
		align-items: center;
		color: var(--color-sidebar-foreground);
	}

	.name {
		flex: 1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
