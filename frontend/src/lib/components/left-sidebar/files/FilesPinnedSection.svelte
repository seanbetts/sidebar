<script lang="ts">
  import type { IngestionListItem } from '$lib/types/ingestion';
  import FilesPinnedItem from '$lib/components/left-sidebar/files/FilesPinnedItem.svelte';

  export let pinnedItems: IngestionListItem[] = [];
  export let dragOverPinnedId: string | null = null;
  export let openMenuKey: string | null = null;
  export let pinnedDropEndId = '';
  export let iconForCategory: (category: string | null | undefined) => typeof import('lucide-svelte').SvelteComponent;
  export let stripExtension: (name: string) => string;

  export let onOpen: (item: IngestionListItem) => void;
  export let onToggleMenu: (event: MouseEvent, menuKey: string) => void;
  export let onRename: (item: IngestionListItem) => void;
  export let onPinToggle: (item: IngestionListItem) => void;
  export let onDownload: (item: IngestionListItem) => void;
  export let onDelete: (item: IngestionListItem, event?: MouseEvent) => void;

  export let onDragStart: (event: DragEvent, id: string) => void;
  export let onDragOver: (event: DragEvent, id: string) => void;
  export let onDrop: (event: DragEvent, id: string) => void;
  export let onDropEnd: (event: DragEvent) => void;
  export let onDragEnd: () => void;
</script>

<div class="files-block">
  <div class="files-block-title">Pinned</div>
  {#if pinnedItems.length > 0}
    <div class="files-block-list">
      {#each pinnedItems as item (item.file.id)}
        <FilesPinnedItem
          {item}
          icon={iconForCategory(item.file.category)}
          menuKey={`pinned-${item.file.id}`}
          {openMenuKey}
          displayName={stripExtension(item.file.filename_original)}
          dragOver={dragOverPinnedId === item.file.id}
          onOpen={onOpen}
          onToggleMenu={onToggleMenu}
          onRename={onRename}
          onPinToggle={onPinToggle}
          onDownload={onDownload}
          onDelete={onDelete}
          onDragStart={onDragStart}
          onDragOver={onDragOver}
          onDrop={onDrop}
          onDragEnd={onDragEnd}
        />
      {/each}
      <div
        class="pinned-drop-zone"
        class:drag-over={dragOverPinnedId === pinnedDropEndId}
        role="separator"
        aria-label="Drop pinned file at end"
        ondragover={(event) => onDragOver(event, pinnedDropEndId)}
        ondrop={onDropEnd}
      ></div>
    </div>
  {:else}
    <div class="files-empty">No pinned files</div>
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

  .files-empty {
    padding: 0.5rem 0.25rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }

  .pinned-drop-zone {
    position: relative;
    height: 12px;
  }

  .pinned-drop-zone.drag-over::before {
    content: '';
    position: absolute;
    left: 0.5rem;
    right: 0.5rem;
    bottom: 0;
    height: 2px;
    border-radius: 999px;
    background: var(--color-sidebar-border);
  }
</style>
