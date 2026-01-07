<script lang="ts">
  import { FileText, Save, Clock, X, Pencil, FolderInput, Archive, ArchiveRestore, Pin, PinOff, Copy, Check, Download, Trash2, Menu } from 'lucide-svelte';
  import * as Popover from '$lib/components/ui/popover/index.js';
  import { Button } from '$lib/components/ui/button';
  import { Tooltip, TooltipContent, TooltipTrigger } from '$lib/components/ui/tooltip';
  import { TOOLTIP_COPY } from '$lib/constants/tooltips';
  import { canShowTooltips } from '$lib/utils/tooltip';

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
  let isMoveOpenCompact = false;
  let didRequestMoveOptions = false;
  let tooltipsEnabled = false;

  $: if ((isMoveOpen || isMoveOpenCompact) && !didRequestMoveOptions) {
    didRequestMoveOptions = true;
    onMoveOpen();
  }

  $: if (!isMoveOpen && !isMoveOpenCompact && didRequestMoveOptions) {
    didRequestMoveOptions = false;
  }

  $: tooltipsEnabled = canShowTooltips();
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
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onCopy}
              aria-label={isCopied ? 'Copied preview' : 'Copy preview'}
            >
              {#if isCopied}
                <Check size={16} />
              {:else}
                <Copy size={16} />
              {/if}
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">
            {isCopied ? TOOLTIP_COPY.copy.success : 'Copy preview'}
          </TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onClose}
              aria-label="Close preview"
            >
              <X size={16} />
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.close}</TooltipContent>
        </Tooltip>
      {:else}
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onPinToggle}
              aria-label="Pin note"
            >
              {#if noteNode?.pinned}
                <PinOff size={16} />
              {:else}
                <Pin size={16} />
              {/if}
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">
            {noteNode?.pinned ? TOOLTIP_COPY.pin.on : TOOLTIP_COPY.pin.off}
          </TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onRename}
              aria-label="Rename note"
            >
              <Pencil size={16} />
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.rename}</TooltipContent>
        </Tooltip>
        {#if !noteNode?.archived}
          <Popover.Root bind:open={isMoveOpen}>
            <Popover.Trigger>
              {#snippet child({ props })}
                <Tooltip disabled={!tooltipsEnabled}>
                  <TooltipTrigger asChild>
                    <Button size="icon" variant="ghost" {...props} aria-label="Move note">
                      <FolderInput size={16} />
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent side="bottom">{TOOLTIP_COPY.move}</TooltipContent>
                </Tooltip>
              {/snippet}
            </Popover.Trigger>
            <Popover.Content class="note-move-menu" align="start" sideOffset={8}>
              {#each folderOptions as option (option.value)}
                <button
                  class="note-move-item"
                  style={`padding-left: ${option.depth * 12 + 12}px`}
                  onclick={() => onMove(option.value)}
                >
                  {option.label}
                </button>
              {/each}
            </Popover.Content>
          </Popover.Root>
        {/if}
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onCopy}
              aria-label={isCopied ? 'Copied note' : 'Copy note'}
            >
              {#if isCopied}
                <Check size={16} />
              {:else}
                <Copy size={16} />
              {/if}
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">
            {isCopied ? TOOLTIP_COPY.copy.success : TOOLTIP_COPY.copy.default}
          </TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onDownload}
              aria-label="Download note"
            >
              <Download size={16} />
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.downloadMarkdown}</TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={noteNode?.archived ? onUnarchive : onArchive}
              aria-label={noteNode?.archived ? 'Unarchive note' : 'Archive note'}
            >
              {#if noteNode?.archived}
                <ArchiveRestore size={16} />
              {:else}
                <Archive size={16} />
              {/if}
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">
            {noteNode?.archived ? TOOLTIP_COPY.archive.on : TOOLTIP_COPY.archive.off}
          </TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onDelete}
              aria-label="Delete note"
            >
              <Trash2 size={16} />
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.delete}</TooltipContent>
        </Tooltip>
        <Tooltip disabled={!tooltipsEnabled}>
          <TooltipTrigger asChild>
            <Button
              size="icon"
              variant="ghost"
              onclick={onClose}
              aria-label="Close note"
            >
              <X size={16} />
            </Button>
          </TooltipTrigger>
          <TooltipContent side="bottom">{TOOLTIP_COPY.close}</TooltipContent>
        </Tooltip>
      {/if}
    </div>
    <div class="note-actions-compact">
      <Popover.Root>
        <Popover.Trigger>
          {#snippet child({ props })}
            <Tooltip disabled={!tooltipsEnabled}>
              <TooltipTrigger asChild>
                <Button size="icon" variant="ghost" {...props} aria-label="More actions">
                  <Menu size={16} />
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">More actions</TooltipContent>
            </Tooltip>
          {/snippet}
        </Popover.Trigger>
        <Popover.Content class="note-actions-menu" align="end" sideOffset={8}>
          {#if isReadOnly}
            <button class="note-menu-item" onclick={onCopy}>
              {#if isCopied}
                <Check size={16} />
                <span>Copied</span>
              {:else}
                <Copy size={16} />
                <span>Copy</span>
              {/if}
            </button>
            <button class="note-menu-item" onclick={onClose}>
              <X size={16} />
              <span>Close</span>
            </button>
          {:else}
            <button class="note-menu-item" onclick={onPinToggle}>
              {#if noteNode?.pinned}
                <PinOff size={16} />
                <span>Unpin</span>
              {:else}
                <Pin size={16} />
                <span>Pin</span>
              {/if}
            </button>
            <button class="note-menu-item" onclick={onRename}>
              <Pencil size={16} />
              <span>Rename</span>
            </button>
            {#if !noteNode?.archived}
              <Popover.Root bind:open={isMoveOpenCompact}>
                <Popover.Trigger>
                  {#snippet child({ props })}
                    <button class="note-menu-item" {...props}>
                      <FolderInput size={16} />
                      <span>Move</span>
                    </button>
                  {/snippet}
                </Popover.Trigger>
                <Popover.Content class="note-move-menu" align="start" sideOffset={8}>
                  {#each folderOptions as option (option.value)}
                    <button
                      class="note-move-item"
                      style={`padding-left: ${option.depth * 12 + 12}px`}
                      onclick={() => onMove(option.value)}
                    >
                      {option.label}
                    </button>
                  {/each}
                </Popover.Content>
              </Popover.Root>
            {/if}
            <button class="note-menu-item" onclick={onCopy}>
              {#if isCopied}
                <Check size={16} />
                <span>Copied</span>
              {:else}
                <Copy size={16} />
                <span>Copy</span>
              {/if}
            </button>
            <button class="note-menu-item" onclick={onDownload}>
              <Download size={16} />
              <span>Download</span>
            </button>
            <button class="note-menu-item" onclick={noteNode?.archived ? onUnarchive : onArchive}>
              {#if noteNode?.archived}
                <ArchiveRestore size={16} />
                <span>Unarchive</span>
              {:else}
                <Archive size={16} />
                <span>Archive</span>
              {/if}
            </button>
            <button class="note-menu-item" onclick={onDelete}>
              <Trash2 size={16} />
              <span>Delete</span>
            </button>
            <button class="note-menu-item" onclick={onClose}>
              <X size={16} />
              <span>Close</span>
            </button>
          {/if}
        </Popover.Content>
      </Popover.Root>
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
    container-type: inline-size;
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

  .note-actions-compact {
    display: none;
  }

  :global(.note-actions-menu) {
    width: max-content !important;
    min-width: 0 !important;
    padding: 0.25rem 0;
  }

  .note-menu-item {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    width: 100%;
    border: none;
    background: none;
    cursor: pointer;
    padding: 0.45rem 0.75rem;
    text-align: left;
    font-size: 0.8rem;
    color: var(--color-popover-foreground);
  }

  .note-menu-item:hover {
    background-color: var(--color-accent);
  }

  .status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.75rem;
    padding: 0 0.75rem;
    border-radius: 0.375rem;
  }

  :global(.note-move-menu) {
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

  @container (max-width: 700px) {
    .note-actions {
      display: none;
    }

    .note-actions-compact {
      display: inline-flex;
      align-items: center;
    }
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
