<script lang="ts">
  import { Trash2, X } from 'lucide-svelte';
  import type { Memory } from '$lib/types/memory';

  export let open = false;
  export let memory: Memory | null = null;
  export let nameValue = '';
  export let saveState: 'idle' | 'dirty' | 'saving' | 'saved' | 'error' = 'idle';
  export let editorElement: HTMLDivElement | null = null;
  export let onNameInput: (value: string) => void;
  export let onClose: () => void;
  export let onDelete: () => void;
</script>

{#if open && memory}
  <div class="memory-modal">
    <button
      class="memory-modal-overlay"
      type="button"
      aria-label="Close edit memory dialog"
      on:click={onClose}
    ></button>
    <div class="memory-modal-content" role="dialog" aria-modal="true">
      <div class="memory-modal-header">
        <div>
          <h4>Edit memory</h4>
          <p class="memory-status {saveState}">
            {#if saveState === 'saving'}
              Saving…
            {:else if saveState === 'saved'}
              Saved
            {:else if saveState === 'error'}
              Save failed
            {:else if saveState === 'dirty'}
              Unsaved changes
            {:else}
              Auto-save enabled
            {/if}
          </p>
        </div>
        <button class="icon-button" on:click={onClose}>
          <X size={16} />
        </button>
      </div>
      <label class="settings-label">
        <span>Name</span>
        <input
          class="settings-input"
          type="text"
          value={nameValue}
          on:input={(event) => onNameInput((event.target as HTMLInputElement).value)}
        />
      </label>
      <div class="settings-label">
        <span>Content</span>
        <div class="memory-editor" role="group" aria-label="Memory content">
          <div class="memory-editor-surface" bind:this={editorElement}></div>
        </div>
      </div>
      <div class="memory-modal-actions">
        <button class="settings-button secondary" on:click={onClose}>
          Done
        </button>
        <button class="settings-button ghost" on:click={onDelete}>
          <Trash2 size={14} />
          Delete
        </button>
      </div>
    </div>
  </div>
{/if}
