<script lang="ts">
  import { MoreVertical, Trash2 } from 'lucide-svelte';
  import type { Conversation } from '$lib/types/history';
  import { chatStore } from '$lib/stores/chat';
  import { conversationListStore, currentConversationId } from '$lib/stores/conversations';

  export let conversation: Conversation;

  let showMenu = false;
  let isActive = false;

  $: isActive = $currentConversationId === conversation.id;

  async function handleClick() {
    currentConversationId.set(conversation.id);
    await chatStore.loadConversation(conversation.id);
    showMenu = false;
  }

  async function handleDelete(event: MouseEvent) {
    event.stopPropagation();
    if (confirm(`Delete "${conversation.title}"?`)) {
      await conversationListStore.deleteConversation(conversation.id);
      if (isActive) {
        chatStore.reset();
        currentConversationId.set(null);
      }
    }
    showMenu = false;
  }

  function toggleMenu(event: MouseEvent) {
    event.stopPropagation();
    showMenu = !showMenu;
  }

  function formatDate(dateString: string): string {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffMins < 1440) return `${Math.floor(diffMins / 60)}h ago`;
    return date.toLocaleDateString();
  }
</script>

<div class="conversation-item" class:active={isActive} on:click={handleClick} role="button" tabindex="0">
  <div class="content">
    <div class="title">{conversation.title}</div>
    {#if conversation.firstMessage}
      <div class="preview">{conversation.firstMessage}</div>
    {/if}
    <div class="meta">
      <span class="timestamp">{formatDate(conversation.updatedAt)}</span>
      <span class="message-count">{conversation.messageCount} messages</span>
    </div>
  </div>

  <div class="actions">
    <button class="menu-btn" on:click={toggleMenu} aria-label="More options">
      <MoreVertical size={16} />
    </button>

    {#if showMenu}
      <div class="menu">
        <button class="menu-item delete" on:click={handleDelete}>
          <Trash2 size={16} />
          <span>Delete</span>
        </button>
      </div>
    {/if}
  </div>
</div>

<style>
  .conversation-item {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    padding: 0.75rem 1rem;
    cursor: pointer;
    transition: background-color 0.2s;
    border-left: 2px solid transparent;
    color: var(--color-sidebar-foreground);
  }

  .conversation-item:hover {
    background-color: var(--color-sidebar-accent);
  }

  .conversation-item.active {
    background-color: var(--color-sidebar-accent);
    border-left-color: var(--color-sidebar-primary);
  }

  .content {
    flex: 1;
    min-width: 0;
  }

  .title {
    font-weight: 500;
    font-size: 0.875rem;
    margin-bottom: 0.25rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--color-sidebar-foreground);
  }

  .preview {
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    margin-bottom: 0.25rem;
  }

  .meta {
    display: flex;
    gap: 0.5rem;
    font-size: 0.75rem;
    color: var(--color-muted-foreground);
    opacity: 0.7;
  }

  .actions {
    position: relative;
    display: flex;
    align-items: flex-start;
  }

  .menu-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.25rem;
    background: none;
    border: none;
    cursor: pointer;
    border-radius: 0.25rem;
    color: var(--color-muted-foreground);
    opacity: 0;
    transition: all 0.2s;
  }

  .conversation-item:hover .menu-btn {
    opacity: 1;
  }

  .menu-btn:hover {
    background-color: var(--color-accent);
  }

  .menu {
    position: absolute;
    top: 100%;
    right: 0;
    margin-top: 0.25rem;
    background-color: var(--color-popover);
    border: 1px solid var(--color-border);
    border-radius: 0.375rem;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    z-index: 10;
    min-width: 120px;
  }

  .menu-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.5rem 0.75rem;
    background: none;
    border: none;
    cursor: pointer;
    font-size: 0.875rem;
    text-align: left;
    transition: background-color 0.2s;
    color: var(--color-popover-foreground);
  }

  .menu-item:hover {
    background-color: var(--color-accent);
  }

  .menu-item.delete {
    color: var(--color-destructive);
  }
</style>
