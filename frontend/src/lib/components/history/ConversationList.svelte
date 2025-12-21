<script lang="ts">
  import { groupedConversations, conversationListStore } from '$lib/stores/conversations';
  import ConversationItem from './ConversationItem.svelte';

  const groupLabels = {
    today: 'Today',
    yesterday: 'Yesterday',
    lastWeek: 'Last 7 days',
    lastMonth: 'Last 30 days',
    older: 'Older'
  };
</script>

<div class="conversation-list">
  {#if $conversationListStore.loading}
    <div class="loading">Loading conversations...</div>
  {:else if $conversationListStore.conversations.length === 0}
    <div class="empty">
      {#if $conversationListStore.searchQuery}
        <p>No conversations found matching "{$conversationListStore.searchQuery}"</p>
      {:else}
        <p>No conversations yet</p>
        <p class="hint">Start a new chat to begin</p>
      {/if}
    </div>
  {:else}
    {#each Object.entries($groupedConversations) as [groupKey, conversations]}
      {#if conversations.length > 0}
        <div class="group">
          <div class="group-label">{groupLabels[groupKey]}</div>
          {#each conversations as conversation (conversation.id)}
            <ConversationItem {conversation} />
          {/each}
        </div>
      {/if}
    {/each}
  {/if}
</div>

<style>
  .conversation-list {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
  }

  .loading,
  .empty {
    padding: 2rem 1rem;
    text-align: center;
    color: var(--color-text-secondary, #666);
    font-size: 0.875rem;
  }

  .empty p {
    margin: 0.5rem 0;
  }

  .empty .hint {
    font-size: 0.75rem;
    color: var(--color-text-tertiary, #999);
  }

  .group {
    margin-bottom: 1rem;
  }

  .group-label {
    padding: 0.5rem 1rem;
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--color-text-secondary, #666);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  /* Custom scrollbar */
  .conversation-list::-webkit-scrollbar {
    width: 6px;
  }

  .conversation-list::-webkit-scrollbar-track {
    background: transparent;
  }

  .conversation-list::-webkit-scrollbar-thumb {
    background: var(--color-border, #e0e0e0);
    border-radius: 3px;
  }

  .conversation-list::-webkit-scrollbar-thumb:hover {
    background: var(--color-text-tertiary, #999);
  }
</style>
