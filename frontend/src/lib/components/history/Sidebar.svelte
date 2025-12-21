<script lang="ts">
  import { onMount } from 'svelte';
  import { ChevronLeft, ChevronRight, Plus, MessageSquare, Folder, FileText } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import CollapsibleSection from '$lib/components/sidebar/CollapsibleSection.svelte';
  import SearchBar from './SearchBar.svelte';
  import ConversationList from './ConversationList.svelte';
  import FileTree from '$lib/components/files/FileTree.svelte';

  let isCollapsed = false;

  onMount(() => {
    conversationListStore.load();
  });

  async function handleNewChat() {
    await chatStore.clear();
    await conversationListStore.refresh();
  }

  function toggleSidebar() {
    isCollapsed = !isCollapsed;
  }
</script>

<div class="sidebar" class:collapsed={isCollapsed}>
  <div class="sidebar-content">
    <!-- Header -->
    <div class="header">
      {#if !isCollapsed}
        <h2>Sidebar</h2>
        <button on:click={toggleSidebar} class="collapse-btn" aria-label="Collapse sidebar">
          <ChevronLeft size={20} />
        </button>
      {:else}
        <button on:click={toggleSidebar} class="collapse-btn" aria-label="Expand sidebar">
          <ChevronRight size={20} />
        </button>
      {/if}
    </div>

    {#if !isCollapsed}
      <!-- New Chat Button -->
      <button on:click={handleNewChat} class="new-chat-btn">
        <Plus size={20} />
        <span>New Chat</span>
      </button>

      <!-- Universal Search Bar -->
      <div class="search-container">
        <SearchBar />
      </div>

      <div class="sections">
        <!-- History Section -->
        <CollapsibleSection title="History" icon={MessageSquare} defaultExpanded={true}>
          <div class="history-content">
            <ConversationList />
          </div>
        </CollapsibleSection>

        <!-- Notes Section -->
        <CollapsibleSection title="Notes" icon={FileText} defaultExpanded={false}>
          <div class="notes-content">
            <FileTree basePath="notes" emptyMessage="No notes found" hideExtensions={true} />
          </div>
        </CollapsibleSection>

        <!-- Documents Section -->
        <CollapsibleSection title="Documents" icon={Folder} defaultExpanded={false}>
          <div class="files-content">
            <FileTree basePath="documents" emptyMessage="No files found" hideExtensions={false} />
          </div>
        </CollapsibleSection>
      </div>
    {/if}
  </div>
</div>

<style>
  .sidebar {
    display: flex;
    flex-direction: column;
    height: 100vh;
    width: 260px;
    background-color: var(--color-sidebar);
    border-right: 1px solid var(--color-sidebar-border);
    transition: width 0.2s ease;
  }

  .sidebar.collapsed {
    width: 60px;
  }

  .sidebar-content {
    display: flex;
    flex-direction: column;
    height: 100%;
    overflow: hidden;
  }

  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem;
    border-bottom: 1px solid var(--color-sidebar-border);
  }

  .header h2 {
    font-size: 1.125rem;
    font-weight: 600;
    margin: 0;
    color: var(--color-sidebar-foreground);
  }

  .collapse-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.5rem;
    background: none;
    border: none;
    cursor: pointer;
    border-radius: 0.375rem;
    color: var(--color-muted-foreground);
    transition: background-color 0.2s;
  }

  .collapse-btn:hover {
    background-color: var(--color-sidebar-accent);
  }

  .new-chat-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin: 1rem;
    padding: 0.75rem 1rem;
    background-color: var(--color-sidebar-primary);
    color: var(--color-sidebar-primary-foreground);
    border: none;
    border-radius: 0.5rem;
    cursor: pointer;
    font-weight: 500;
    transition: opacity 0.2s;
  }

  .new-chat-btn:hover {
    opacity: 0.9;
  }

  .search-container {
    padding: 0 1rem 1rem 1rem;
  }

  .sections {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
  }

  .history-content {
    display: flex;
    flex-direction: column;
  }

  .notes-content {
    display: flex;
    flex-direction: column;
  }

  .files-content {
    display: flex;
    flex-direction: column;
  }
</style>
