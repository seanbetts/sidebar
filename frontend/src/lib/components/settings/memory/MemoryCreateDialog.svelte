<script lang="ts">
  import { X } from 'lucide-svelte';

  export let open = false;
  export let nameValue = '';
  export let contentValue = '';
  export let onCreate: () => void;
  export let onClose: () => void;
</script>

{#if open}
  <div class="memory-modal">
    <button
      class="memory-modal-overlay"
      type="button"
      aria-label="Close create memory dialog"
      on:click={onClose}
    ></button>
    <div class="memory-modal-content" role="dialog" aria-modal="true">
      <div class="memory-modal-header">
        <div>
          <h4>Add memory</h4>
          <p>Write a short, stable fact. It will autosave.</p>
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
          bind:value={nameValue}
          placeholder="project_context"
        />
      </label>
      <label class="settings-label">
        <span>Content</span>
        <textarea
          class="settings-textarea"
          rows="6"
          bind:value={contentValue}
          placeholder="Write a short memory entry."
        ></textarea>
      </label>
      <div class="memory-modal-actions">
        <button class="settings-button secondary" on:click={onClose}>
          Cancel
        </button>
        <button class="settings-button" on:click={onCreate}>Create</button>
      </div>
    </div>
  </div>
{/if}
