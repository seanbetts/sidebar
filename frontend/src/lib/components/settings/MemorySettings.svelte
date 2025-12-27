<script lang="ts">
  import { onDestroy, onMount, tick } from 'svelte';
  import { get } from 'svelte/store';
  import { Editor } from '@tiptap/core';
  import StarterKit from '@tiptap/starter-kit';
  import { Image } from '@tiptap/extension-image';
  import { TaskList, TaskItem } from '@tiptap/extension-list';
  import { TableKit } from '@tiptap/extension-table';
  import { Markdown } from 'tiptap-markdown';
  import { memoriesStore } from '$lib/stores/memories';
  import type { Memory } from '$lib/types/memory';
  import ChatMarkdown from '$lib/components/chat/ChatMarkdown.svelte';
  import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow
  } from '$lib/components/ui/table';
  import { Loader2, Pencil, Plus, Search, Trash2, X } from 'lucide-svelte';

  let searchTerm = '';
  let showCreateDialog = false;
  let showEditDialog = false;
  let activeMemoryId: string | null = null;
  let createName = '';
  let createContent = '';
  let editorElement: HTMLDivElement | null = null;
  let editor: Editor | null = null;
  let isSyncingEditor = false;

  let draftById: Record<string, { path: string; name: string; content: string }> = {};
  let saveStateById: Record<string, 'idle' | 'dirty' | 'saving' | 'saved' | 'error'> = {};
  let saveTimers: Record<string, ReturnType<typeof setTimeout>> = {};

  const resetDrafts = (memories: Memory[]) => {
    const nextDrafts: Record<string, { path: string; name: string; content: string }> = {};
    const nextStates: Record<string, 'idle' | 'dirty' | 'saving' | 'saved' | 'error'> = {};

    for (const memory of memories) {
      const existing = draftById[memory.id];
      const canSync = !existing || saveStateById[memory.id] === 'idle' || saveStateById[memory.id] === 'saved';
      if (canSync) {
        nextDrafts[memory.id] = {
          path: memory.path,
          name: displayName(memory.path),
          content: memory.content
        };
        nextStates[memory.id] = saveStateById[memory.id] ?? 'idle';
      } else if (existing) {
        nextDrafts[memory.id] = existing;
        nextStates[memory.id] = saveStateById[memory.id] ?? 'dirty';
      }
    }

    draftById = nextDrafts;
    saveStateById = nextStates;
  };

  onMount(() => {
    memoriesStore.load();
  });

  onDestroy(() => {
    editor?.destroy();
    editor = null;
  });

  $: resetDrafts($memoriesStore.memories);

  function displayName(path: string) {
    let trimmed = path.startsWith('/memories/') ? path.slice('/memories/'.length) : path;
    if (trimmed.endsWith('.md')) trimmed = trimmed.slice(0, -3);
    return trimmed || 'untitled';
  }

  function buildPathFromName(name: string, fallbackPath?: string) {
    const trimmed = name.trim();
    if (!trimmed) return fallbackPath ?? '/memories/untitled.md';
    const basePath = trimmed.replace(/^\/?memories\/?/, '');
    const hasExtension = basePath.split('/').pop()?.includes('.') ?? false;
    if (basePath.includes('/')) {
      return `/memories/${hasExtension ? basePath : `${basePath}.md`}`;
    }
    if (fallbackPath) {
      const lastSlash = fallbackPath.lastIndexOf('/');
      const dir = lastSlash > 0 ? fallbackPath.slice(0, lastSlash + 1) : '/memories/';
      const ext = fallbackPath.includes('.') ? fallbackPath.slice(fallbackPath.lastIndexOf('.')) : '.md';
      return `${dir}${hasExtension ? basePath : `${basePath}${ext}`}`;
    }
    return `/memories/${hasExtension ? basePath : `${basePath}.md`}`;
  }

  async function createMemory() {
    if (!createName.trim() || !createContent.trim()) return;
    const path = buildPathFromName(createName);
    const created = await memoriesStore.create({
      path,
      content: createContent
    });
    if (created) {
      createName = '';
      createContent = '';
      showCreateDialog = false;
    }
  }

  async function openEditor(memory: Memory) {
    activeMemoryId = memory.id;
    showEditDialog = true;
    await tick();
    ensureEditor();
    syncEditorContent();
  }

  function closeEditor() {
    showEditDialog = false;
    activeMemoryId = null;
    editor?.destroy();
    editor = null;
  }

  function scheduleSave(memoryId: string) {
    const draft = draftById[memoryId];
    const memory = get(memoriesStore).memories.find((item) => item.id === memoryId);
    if (!draft || !memory) return;
    const nextPath = buildPathFromName(draft.name, draft.path);
    const nextContent = draft.content;

    if (nextPath === memory.path && nextContent === memory.content) {
      saveStateById[memoryId] = 'idle';
      return;
    }

    saveStateById[memoryId] = 'dirty';
    if (saveTimers[memoryId]) clearTimeout(saveTimers[memoryId]);
    saveTimers[memoryId] = setTimeout(async () => {
      saveStateById[memoryId] = 'saving';
      try {
        await memoriesStore.updateMemory(memoryId, {
          path: nextPath,
          content: nextContent
        });
        saveStateById[memoryId] = 'saved';
        setTimeout(() => {
          if (saveStateById[memoryId] === 'saved') saveStateById[memoryId] = 'idle';
        }, 1200);
      } catch {
        saveStateById[memoryId] = 'error';
      }
    }, 650);
  }

  async function deleteMemory(memory: Memory) {
    await memoriesStore.delete(memory.id);
    if (memory.id === activeMemoryId) {
      closeEditor();
    }
  }

  function ensureEditor() {
    if (!editorElement || editor) return;
    editor = new Editor({
      element: editorElement,
      extensions: [
        StarterKit,
        Image.configure({ inline: false, allowBase64: true }),
        TaskList,
        TaskItem.configure({ nested: true }),
        TableKit,
        Markdown
      ],
      content: '',
      editable: true,
      editorProps: {
        attributes: {
          class: 'tiptap memory-markdown prose prose-sm max-w-none'
        }
      },
      onUpdate: ({ editor }) => {
        if (!activeMemoryId || isSyncingEditor) return;
        const markdown = editor.storage.markdown.getMarkdown();
        const draft = draftById[activeMemoryId];
        if (!draft || draft.content === markdown) return;
        draftById = {
          ...draftById,
          [activeMemoryId]: {
            ...draft,
            content: markdown
          }
        };
        scheduleSave(activeMemoryId);
      }
    });
  }

  function syncEditorContent() {
    if (!editor || !activeMemoryId) return;
    const draft = draftById[activeMemoryId];
    if (!draft) return;
    const current = editor.storage.markdown.getMarkdown();
    if (current === draft.content) return;
    isSyncingEditor = true;
    editor.commands.setContent(draft.content || '');
    isSyncingEditor = false;
  }

  $: activeMemory =
    activeMemoryId && $memoriesStore.memories
      ? $memoriesStore.memories.find((memory) => memory.id === activeMemoryId) ?? null
      : null;

  $: if (showEditDialog && activeMemoryId && editor && draftById[activeMemoryId]) {
    syncEditorContent();
  }

  $: filteredMemories =
    $memoriesStore.memories?.filter((memory) => {
      const draft = draftById[memory.id];
      const name = draft ? draft.name : displayName(memory.path);
      const content = draft ? draft.content : memory.content;
      const haystack = `${name} ${content}`.toLowerCase();
      return haystack.includes(searchTerm.trim().toLowerCase());
    }) ?? [];
</script>

<section class="memory-settings">
  <div class="settings-section-header">
    <h3>Memory</h3>
    <p>Store stable facts about you, projects, and relationships. Avoid preferences.</p>
  </div>

  <div class="memory-toolbar">
    <div class="memory-search">
      <Search size={14} />
      <input
        class="memory-search-input"
        type="text"
        placeholder="Search memories"
        bind:value={searchTerm}
      />
    </div>
    <button class="settings-button" on:click={() => (showCreateDialog = true)}>
      <Plus size={14} />
      Add Memory
    </button>
  </div>

  {#if $memoriesStore.isLoading}
    <div class="settings-meta">
      <Loader2 size={16} class="spin" />
      Loading memories...
    </div>
  {:else if $memoriesStore.error}
    <div class="settings-error">{$memoriesStore.error}</div>
  {:else if $memoriesStore.memories.length === 0}
    <div class="settings-meta">No memories stored yet.</div>
  {:else if filteredMemories.length === 0}
    <div class="settings-meta">No memories match that search.</div>
  {:else}
    <div class="memory-table-wrapper">
      <Table class="memory-table">
        <colgroup>
          <col />
          <col style="width: 96px" />
          <col style="width: 64px" />
          <col style="width: 64px" />
        </colgroup>
        <TableHeader>
          <TableRow>
            <TableHead>Name</TableHead>
            <TableHead class="memory-col-updated">Updated</TableHead>
            <TableHead class="memory-col-action memory-col-action-head">Edit</TableHead>
            <TableHead class="memory-col-action memory-col-action-head">Delete</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {#each filteredMemories as memory (memory.id)}
            <TableRow class="memory-row">
              <TableCell class="memory-name-cell">
                {draftById[memory.id]?.name ?? displayName(memory.path)}
              </TableCell>
              <TableCell class="memory-updated">
                {new Date(memory.updated_at).toLocaleDateString()}
              </TableCell>
              <TableCell class="memory-action-cell memory-col-action-cell">
                <button class="settings-button ghost icon" on:click={() => openEditor(memory)} aria-label="Edit memory">
                  <Pencil size={14} />
                </button>
              </TableCell>
              <TableCell class="memory-action-cell memory-col-action-cell">
                <button class="settings-button ghost icon" on:click={() => deleteMemory(memory)} aria-label="Delete memory">
                  <Trash2 size={14} />
                </button>
              </TableCell>
            </TableRow>
          {/each}
        </TableBody>
      </Table>
    </div>
  {/if}
</section>

{#if showCreateDialog}
  <div class="memory-modal">
    <button
      class="memory-modal-overlay"
      type="button"
      aria-label="Close create memory dialog"
      on:click={() => (showCreateDialog = false)}
    ></button>
    <div class="memory-modal-content" role="dialog" aria-modal="true">
      <div class="memory-modal-header">
        <div>
          <h4>Add memory</h4>
          <p>Write a short, stable fact. It will autosave.</p>
        </div>
        <button class="icon-button" on:click={() => (showCreateDialog = false)}>
          <X size={16} />
        </button>
      </div>
      <label class="settings-label">
        <span>Name</span>
        <input
          class="settings-input"
          type="text"
          bind:value={createName}
          placeholder="project_context"
        />
      </label>
      <label class="settings-label">
        <span>Content</span>
        <textarea
          class="settings-textarea"
          rows="6"
          bind:value={createContent}
          placeholder="Write a short memory entry."
        ></textarea>
      </label>
      <div class="memory-modal-actions">
        <button class="settings-button secondary" on:click={() => (showCreateDialog = false)}>
          Cancel
        </button>
        <button class="settings-button" on:click={createMemory}>Create</button>
      </div>
    </div>
  </div>
{/if}

{#if showEditDialog && activeMemoryId && activeMemory}
  <div class="memory-modal">
    <button
      class="memory-modal-overlay"
      type="button"
      aria-label="Close edit memory dialog"
      on:click={closeEditor}
    ></button>
    <div class="memory-modal-content" role="dialog" aria-modal="true">
      <div class="memory-modal-header">
        <div>
          <h4>Edit memory</h4>
          <p class="memory-status {saveStateById[activeMemoryId]}">
            {#if saveStateById[activeMemoryId] === 'saving'}
              Saving…
            {:else if saveStateById[activeMemoryId] === 'saved'}
              Saved
            {:else if saveStateById[activeMemoryId] === 'error'}
              Save failed
            {:else if saveStateById[activeMemoryId] === 'dirty'}
              Unsaved changes
            {:else}
              Auto-save enabled
            {/if}
          </p>
        </div>
        <button class="icon-button" on:click={closeEditor}>
          <X size={16} />
        </button>
      </div>
      <label class="settings-label">
        <span>Name</span>
        <input
          class="settings-input"
          type="text"
          bind:value={draftById[activeMemoryId].name}
          on:input={() => activeMemoryId && scheduleSave(activeMemoryId)}
        />
      </label>
      <div class="settings-label">
        <span>Content</span>
        <div class="memory-editor" role="group" aria-label="Memory content">
          <div class="memory-editor-surface" bind:this={editorElement}></div>
        </div>
      </div>
      <div class="memory-modal-actions">
        <button class="settings-button secondary" on:click={closeEditor}>
          Done
        </button>
        <button class="settings-button ghost" on:click={() => deleteMemory(activeMemory)}>
          <Trash2 size={14} />
          Delete
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .memory-settings {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .memory-toolbar {
    display: flex;
    gap: 0.75rem;
    align-items: center;
    justify-content: space-between;
  }

  .memory-search {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.45rem 0.65rem;
    border-radius: 0.7rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    color: var(--color-muted-foreground);
  }

  .memory-search-input {
    flex: 1;
    border: none;
    background: transparent;
    color: var(--color-foreground);
    font-size: 0.85rem;
    outline: none;
  }

  .memory-table-wrapper {
    border: 1px solid var(--color-border);
    border-radius: 0.9rem;
    overflow: hidden;
    background: var(--color-card);
  }

  .memory-table {
    table-layout: fixed;
  }

  .memory-row {
    height: 68px;
  }

  .memory-name-cell {
    font-weight: 600;
    color: var(--color-foreground);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .memory-action-cell {
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .memory-updated {
    color: var(--color-muted-foreground);
    font-size: 0.78rem;
    white-space: nowrap;
  }

  .memory-col-updated {
    width: 96px;
  }

  .memory-table :global(.memory-col-action) {
    width: 64px;
    min-width: 64px;
    padding: 0.2rem 0.2rem !important;
    text-align: center;
  }

  .memory-table :global(.memory-col-action-head) {
    text-align: center;
    padding: 0.2rem 0.2rem !important;
  }

  .memory-table :global(.memory-action-cell),
  .memory-table :global(.memory-col-action-cell) {
    text-align: center;
    padding: 0.2rem 0.2rem !important;
    min-width: 64px;
  }

  .memory-table :global(.memory-action-cell .settings-button.icon) {
    padding: 0.2rem;
    width: 28px;
    height: 28px;
  }

  .memory-table :global(.memory-action-cell .settings-button.ghost) {
    padding: 0.2rem;
  }

  .settings-section-header h3 {
    margin: 0 0 0.35rem;
    font-size: 1rem;
    font-weight: 600;
  }

  .settings-section-header p {
    margin: 0 0 0.75rem;
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
  }

  .settings-label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .settings-input,
  .settings-textarea {
    width: 100%;
    padding: 0.55rem 0.65rem;
    border-radius: 0.5rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    color: var(--color-foreground);
    font-size: 0.85rem;
  }

  .settings-textarea {
    resize: vertical;
  }

  .settings-button {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.45rem 0.9rem;
    border-radius: 0.55rem;
    border: none;
    background: var(--color-primary);
    color: var(--color-primary-foreground);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.2s ease;
  }

  .settings-button.secondary {
    background: var(--color-secondary);
    border: 1px solid var(--color-border);
    color: var(--color-secondary-foreground);
  }

  .settings-button.ghost {
    background: transparent;
    border: 1px solid transparent;
    color: var(--color-muted-foreground);
    padding: 0.35rem 0.5rem;
  }

  .settings-meta {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }

  .settings-error {
    color: #c0392b;
    font-size: 0.8rem;
  }

  .memory-modal {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    z-index: 50;
  }

  .memory-modal-overlay {
    position: absolute;
    inset: 0;
    background: rgba(7, 10, 18, 0.6);
  }

  .memory-modal-content {
    position: relative;
    width: min(720px, 92vw);
    background: var(--color-card);
    border-radius: 1rem;
    padding: 1.5rem;
    border: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    gap: 1rem;
    box-shadow: 0 25px 60px rgba(0, 0, 0, 0.2);
  }

  .memory-modal-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 1rem;
  }

  .memory-modal-header h4 {
    margin: 0;
    font-size: 1.1rem;
  }

  .memory-modal-header p {
    margin: 0.25rem 0 0;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .memory-modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 0.6rem;
  }

  .memory-editor {
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-background);
  }

  .memory-editor-surface {
    padding: 0.75rem 0.9rem;
    min-height: 220px;
  }

  :global(.memory-markdown [contenteditable='true']:focus) {
    outline: none;
  }

  .icon-button {
    border: none;
    background: transparent;
    color: var(--color-muted-foreground);
    cursor: pointer;
    padding: 0.25rem;
  }

  .memory-status {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
  }

  .memory-status.saving,
  .memory-status.dirty {
    color: #d9822b;
  }

  .memory-status.saved {
    color: #2d9f7f;
  }

  .memory-status.error {
    color: #c0392b;
  }

  @media (max-width: 720px) {
    .memory-table :global(th:nth-child(2)),
    .memory-table :global(td:nth-child(2)) {
      display: none;
    }

    .memory-toolbar {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
