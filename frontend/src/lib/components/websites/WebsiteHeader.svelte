<script lang="ts">
  import { FileTerminal, Pin, PinOff, Pencil, Copy, Check, Download, Archive, ArchiveRestore, Trash2, X } from 'lucide-svelte';
  import { Button } from '$lib/components/ui/button';
  import type { WebsiteItem } from '$lib/stores/websites';

  export let website: WebsiteItem | null = null;
  export let isCopied = false;
  export let formatDomain: (domain: string) => string;
  export let formatDate: (date: Date) => string;
  export let onPinToggle: () => void;
  export let onRename: () => void;
  export let onCopy: () => void;
  export let onDownload: () => void;
  export let onArchive: () => void;
  export let onDelete: () => void;
  export let onClose: () => void;
</script>

<div class="website-header">
  {#if website}
    <div class="website-meta">
      <div class="title-row">
        <FileTerminal size={18} />
        <span class="title-text">{website.title}</span>
      </div>
      <div class="website-meta-row">
        <span class="subtitle">
          <a class="source" href={website.url} target="_blank" rel="noopener noreferrer">
            <span>{formatDomain(website.domain)}</span>
          </a>
          {#if website.published_at}
            <span class="pipe">|</span>
            <span class="published-date">
              {formatDate(new Date(website.published_at))}
            </span>
          {/if}
        </span>
        <div class="website-actions">
          <Button
            size="icon"
            variant="ghost"
            onclick={onPinToggle}
            aria-label="Pin website"
            title="Pin website"
          >
            {#if website.pinned}
              <PinOff size={16} />
            {:else}
              <Pin size={16} />
            {/if}
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={onRename}
            aria-label="Rename website"
            title="Rename website"
          >
            <Pencil size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={onCopy}
            aria-label={isCopied ? 'Copied website' : 'Copy website'}
            title={isCopied ? 'Copied' : 'Copy website'}
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
            aria-label="Download website"
            title="Download website"
          >
            <Download size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={onArchive}
            aria-label={website.archived ? 'Unarchive website' : 'Archive website'}
            title={website.archived ? 'Unarchive website' : 'Archive website'}
          >
            {#if website.archived}
              <ArchiveRestore size={16} />
            {:else}
              <Archive size={16} />
            {/if}
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={onDelete}
            aria-label="Delete website"
            title="Delete website"
          >
            <Trash2 size={16} />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            onclick={onClose}
            aria-label="Close website"
            title="Close website"
          >
            <X size={16} />
          </Button>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .website-header {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    gap: 1rem;
    padding: 0.5rem 1.5rem;
    min-height: 57px;
    border-bottom: 1px solid var(--color-border);
    background-color: var(--color-card);
  }

  .website-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    width: 100%;
  }

  .title-row {
    display: inline-flex;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .website-meta-row {
    display: inline-flex;
    align-items: center;
    gap: 2rem;
  }

  .subtitle {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .website-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
  }

  .pipe {
    color: var(--color-muted-foreground);
  }

  .title-text {
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .published-date {
    color: var(--color-muted-foreground);
  }

  .website-meta .source {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    color: var(--color-muted-foreground);
    text-decoration: none;
  }
</style>
