<script lang="ts">
	import { ChevronRight, Trash2 } from 'lucide-svelte';
	import type { ComponentType } from 'svelte';
	import * as Collapsible from '$lib/components/ui/collapsible/index.js';
	import IngestionQueue from '$lib/components/files/IngestionQueue.svelte';
	import type { IngestionListItem } from '$lib/types/ingestion';
	import FilesListItem from '$lib/components/left-sidebar/files/FilesListItem.svelte';

	export let processingItems: IngestionListItem[] = [];
	export let failedItems: IngestionListItem[] = [];
	export let readyItems: IngestionListItem[] = [];
	export let openMenuKey: string | null = null;
	export let iconForCategory: (category: string | null | undefined) => ComponentType;
	export let stripExtension: (name: string) => string;

	export let onOpen: (item: IngestionListItem) => void;
	export let onToggleMenu: (event: MouseEvent, menuKey: string) => void;
	export let onRename: (item: IngestionListItem) => void;
	export let onPinToggle: (item: IngestionListItem) => void;
	export let onDownload: (item: IngestionListItem) => void;
	export let onDelete: (item: IngestionListItem, event?: MouseEvent) => void;
</script>

{#if processingItems.length > 0}
	<div class="workspace-uploads uploads-block">
		<IngestionQueue items={processingItems} />
	</div>
{/if}

{#if failedItems.length > 0}
	<div class="workspace-uploads uploads-block">
		<div class="workspace-results-label">Failed uploads</div>
		{#each failedItems as item (item.file.id)}
			<div class="failed-item">
				<div class="failed-header">
					<div class="failed-name">{item.file.filename_original}</div>
					<div class="failed-actions">
						<button
							class="failed-action"
							type="button"
							onclick={(event) => onDelete(item, event)}
							aria-label="Delete upload"
						>
							<Trash2 size={14} />
						</button>
					</div>
				</div>
				<div class="failed-message">
					{item.job.user_message || item.job.error_message || 'Upload failed.'}
					<span class="failed-status">Re-upload to try again.</span>
				</div>
			</div>
		{/each}
	</div>
{/if}

{#if readyItems.length > 0}
	<div class="workspace-uploads uploads-block">
		<Collapsible.Root class="group/collapsible" data-collapsible-root>
			<div
				data-slot="sidebar-group"
				data-sidebar="group"
				class="relative flex w-full min-w-0 flex-col p-2"
			>
				<Collapsible.Trigger
					data-slot="sidebar-group-label"
					data-sidebar="group-label"
					class="archive-trigger"
				>
					<span class="uploads-label">Recent uploads</span>
					<span
						class="archive-chevron transition-transform group-data-[state=open]/collapsible:rotate-90"
					>
						<ChevronRight size={16} />
					</span>
				</Collapsible.Trigger>
				<Collapsible.Content data-slot="collapsible-content" class="archive-content pt-1">
					<div
						data-slot="sidebar-group-content"
						data-sidebar="group-content"
						class="w-full text-sm"
					>
						{#each readyItems as item (item.file.id)}
							<FilesListItem
								{item}
								icon={iconForCategory(item.file.category)}
								menuKey={`recent-${item.file.id}`}
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
				</Collapsible.Content>
			</div>
		</Collapsible.Root>
	</div>
{/if}

<style>
	.workspace-uploads {
		margin-top: auto;
		border-top: 1px solid var(--color-sidebar-border);
		padding-top: 0;
	}

	.uploads-block {
		margin-top: auto;
	}

	.workspace-results-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
		padding: 0 0.25rem;
	}

	.uploads-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-muted-foreground);
		font-weight: 600;
	}

	:global(.archive-trigger) {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		width: 100%;
		border: none;
		background: none;
		cursor: pointer;
		padding: 1rem 0.25rem;
		border-radius: 0.375rem;
		text-align: left;
	}

	:global(.archive-trigger:hover) {
		background-color: var(--color-sidebar-accent);
	}

	.archive-chevron {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
		color: var(--color-muted-foreground);
	}

	:global(.archive-trigger:hover) .archive-chevron,
	:global(.archive-trigger:hover) .uploads-label {
		color: var(--color-foreground);
	}

	:global(.archive-content) {
		max-height: min(80vh, 720px);
		overflow-y: auto;
		padding-right: 0.25rem;
	}

	.failed-item {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		padding: 0.35rem 0.5rem;
		border-radius: 0.4rem;
		background: color-mix(in oklab, var(--color-destructive) 8%, transparent);
	}

	.failed-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}

	.failed-name {
		font-size: 0.85rem;
		color: var(--color-foreground);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.failed-actions {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
	}

	.failed-action {
		border: none;
		background: transparent;
		padding: 0;
		cursor: pointer;
		color: var(--color-muted-foreground);
	}

	.failed-action:hover {
		color: var(--color-foreground);
	}

	.failed-action:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.failed-message {
		font-size: 0.75rem;
		color: var(--color-muted-foreground);
	}

	.failed-status {
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.08em;
	}
</style>
