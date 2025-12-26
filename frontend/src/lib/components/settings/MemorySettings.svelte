<script lang="ts">
  import { onMount } from 'svelte';
  import { memoriesStore } from '$lib/stores/memories';
  import type { Memory } from '$lib/types/memory';
  import { Loader2, Plus, Trash2, Save } from 'lucide-svelte';

  let newPath = '';
  let newContent = '';
  let draftById: Record<string, { path: string; content: string }> = {};

  const resetDrafts = (memories: Memory[]) => {
    draftById = {};
    for (const memory of memories) {
      draftById[memory.id] = {
        path: memory.path,
        content: memory.content
      };
    }
  };

  onMount(() => {
    memoriesStore.load();
  });

  $: resetDrafts($memoriesStore.memories);

  async function createMemory() {
    if (!newPath.trim() || !newContent.trim()) return;
    const created = await memoriesStore.create({
      path: newPath.trim(),
      content: newContent
    });
    if (created) {
      newPath = '';
      newContent = '';
    }
  }

  async function saveMemory(memory: Memory) {
    const draft = draftById[memory.id];
    if (!draft) return;
    await memoriesStore.updateMemory(memory.id, {
      path: draft.path,
      content: draft.content
    });
  }

  async function deleteMemory(memory: Memory) {
    await memoriesStore.delete(memory.id);
  }
</script>

<section class="memory-settings">
  <div class="settings-section-header">
    <h3>Memory</h3>
    <p>Store stable facts about you, projects, and relationships. Avoid preferences.</p>
  </div>

  <div class="memory-create">
    <label class="settings-label">
      <span>Path</span>
      <input
        class="settings-input"
        type="text"
        bind:value={newPath}
        placeholder="/memories/project.md"
      />
    </label>
    <label class="settings-label">
      <span>Content</span>
      <textarea
        class="settings-textarea"
        rows="4"
        bind:value={newContent}
        placeholder="Write a short memory entry in markdown."
      ></textarea>
    </label>
    <div class="memory-actions">
      <button class="settings-button" on:click={createMemory}>
        <Plus size={14} />
        Add memory
      </button>
    </div>
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
  {:else}
    <div class="memory-list">
      {#each $memoriesStore.memories as memory (memory.id)}
        <div class="memory-card">
          <label class="settings-label">
            <span>Path</span>
            <input
              class="settings-input"
              type="text"
              bind:value={draftById[memory.id].path}
            />
          </label>
          <label class="settings-label">
            <span>Content</span>
            <textarea
              class="settings-textarea"
              rows="5"
              bind:value={draftById[memory.id].content}
            ></textarea>
          </label>
          <div class="memory-card-actions">
            <button class="settings-button" on:click={() => saveMemory(memory)}>
              <Save size={14} />
              Save
            </button>
            <button class="settings-button secondary" on:click={() => deleteMemory(memory)}>
              <Trash2 size={14} />
              Delete
            </button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .memory-settings {
    display: flex;
    flex-direction: column;
    gap: 1.5rem;
  }

  .memory-create,
  .memory-card {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
  }

  .memory-actions,
  .memory-card-actions {
    display: flex;
    gap: 0.5rem;
  }

  .memory-list {
    display: flex;
    flex-direction: column;
    gap: 1rem;
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
</style>
