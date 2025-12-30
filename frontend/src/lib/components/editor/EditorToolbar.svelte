<script lang="ts">
  import { FileText, Save, Clock, X, Pencil, FolderInput, Archive, ArchiveRestore, Pin, PinOff, Copy, Check, Download, Trash2 } from 'lucide-svelte';
  import * as Popover from '$lib/components/ui/popover/index.js';
  import { Button } from '$lib/components/ui/button';

  export let displayTitle = '';
  export let lastSavedLabel = '';
  export let isReadOnly = false;
  export let isDirty = false;
  export let isSaving = false;
  export let saveError = '';
  export let noteNode: { pinned?: boolean; archived?: boolean } | null = null;
  export let folderOptions: { label: string; value: string; depth: number }[] = [];
  export let isCopied = false;

  export let onCopy: () => void;
  export let onClose: () => void;
  export let onPinToggle: () => void;
  export let onRename: () => void;
  export let onMoveOpen: () => void;
  export let onMove: (folder: string) => void;
  export let onDownload: () => void;
  export let onArchive: () => void;
  export let onUnarchive: () => void;
  export let onDelete: () => void;

  let isMoveOpen = false;
  let didRequestMoveOptions = false;

  $: if (isMoveOpen && !didRequestMoveOptions) {
    didRequestMoveOptions = true;
    onMoveOpen();
  }

  $: if (!isMoveOpen && didRequestMoveOptions) {
    didRequestMoveOptions = false;
  }
</script>

<div class="editor-header">
  <div class="header-left">
    <FileText size={20} />
    <h2 class="note-title">{displayTitle}</h2>
  </div>
  <div class="header-right">
    {#if isReadOnly}
      <span class="status saved">Read-only preview</span>
    {:else if saveError}
      <span class="status error">{saveError}</span>
    {:else if isSaving}
      <span class="status saving">
        <Save size={16} class="spin" />
        Saving...
      </span>
    {:else if isDirty}
      <span class="status unsaved">Unsaved changes</span>
    {:else if lastSavedLabel}
      <span class="status saved">
        <Clock size={16} />
        Saved {lastSavedLabel}
      </span>
    {/if}
    <div class="note-actions">
      {#if isReadOnly}
        <Button
          size="icon"
          variant="ghost"
          onclick={onCopy}
          aria-label={isCopied ? 'Copied preview' : 'Copy preview'}
          title={isCopied ? 'Copied' : 'Copy preview'}
        >
          {#if isCopied}
            <Check size={16} />
          {:else}
            <Copy size={16} />
          {/if}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={onClose}
          aria-label="Close preview"
          title="Close preview"
        >
          <X size={16} />
        </Button>
      {:else}
        <Button
          size="icon"
          variant="ghost"
          onclick={onPinToggle}
          aria-label="Pin note"
          title="Pin note"
        >
          {#if noteNode?.pinned}
            <PinOff size={16} />
          {:else}
            <Pin size={16} />
          {/if}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={onRename}
          aria-label="Rename note"
          title="Rename note"
        >
          <Pencil size={16} />
        </Button>
        {#if !noteNode?.archived}
          <Popover.Root bind:open={isMoveOpen}>
            <Popover.Trigger>
              {#snippet child({ props })}
                <Button size="icon" variant="ghost" {...props} aria-label="Move note" title="Move note">
                  <FolderInput size={16} />
                </Button>
              {/snippet}
            </Popover.Trigger>
            <Popover.Content class="note-move-menu" align="start" sideOffset={8}>
              {#each folderOptions as option (option.value)}
                <button
                  class="note-move-item"
                  style={`padding-left: ${option.depth * 12 + 12}px`}
                  on:click={() => onMove(option.value)}
                >
                  {option.label}
                </button>
              {/each}
            </Popover.Content>
          </Popover.Root>
        {/if}
        <Button
          size="icon"
          variant="ghost"
          onclick={onCopy}
          aria-label={isCopied ? 'Copied note' : 'Copy note'}
          title={isCopied ? 'Copied' : 'Copy note'}
        >
          {#if isCopied}
            <Check size={16} />
          {:else}
            <Copy size={16} />
          {/if}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={onDownload}
          aria-label="Download note"
          title="Download note"
        >
          <Download size={16} />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={noteNode?.archived ? onUnarchive : onArchive}
          aria-label={noteNode?.archived ? 'Unarchive note' : 'Archive note'}
          title={noteNode?.archived ? 'Unarchive note' : 'Archive note'}
        >
          {#if noteNode?.archived}
            <ArchiveRestore size={16} />
          {:else}
            <Archive size={16} />
          {/if}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={onDelete}
          aria-label="Delete note"
          title="Delete note"
        >
          <Trash2 size={16} />
        </Button>
        <Button
          size="icon"
          variant="ghost"
          onclick={onClose}
          aria-label="Close note"
          title="Close note"
        >
          <X size={16} />
        </Button>
      {/if}
    </div>
  </div>
</div>

<style>
  .editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 1.5rem;
    min-height: 57px;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
    flex-shrink: 0;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    color: var(--color-foreground);
  }

  .note-title {
    margin: 0;
    font-size: 1.125rem;
    font-weight: 600;
    line-height: 1.2;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .note-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.75rem;
    padding: 0 0.75rem;
    border-radius: 0.375rem;
  }

  .note-move-menu {
    width: 220px;
    padding: 0.25rem 0;
  }

  .note-move-item {
    display: block;
    width: 100%;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0.4rem 0.75rem;
    text-align: left;
    font-size: 0.8rem;
    color: var(--color-popover-foreground);
  }

  .note-move-item:hover {
    background-color: var(--color-accent);
  }

  .status.saving {
    color: var(--color-primary);
    background-color: var(--color-primary-muted);
  }

  .status.saved {
    color: var(--color-success);
    background-color: var(--color-success-muted);
  }

  .status.unsaved {
    color: var(--color-warning);
    background-color: var(--color-warning-muted);
  }

  .status.error {
    color: var(--color-destructive);
    background-color: var(--color-destructive-muted);
  }
</style>
