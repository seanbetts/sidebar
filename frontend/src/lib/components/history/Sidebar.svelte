<script lang="ts">
  import { onMount } from 'svelte';
  import { ChevronLeft, ChevronRight, Plus, MessageSquare, Folder, FileText, Settings, User, Monitor, Wrench } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import CollapsibleSection from '$lib/components/sidebar/CollapsibleSection.svelte';
  import SearchBar from './SearchBar.svelte';
  import ConversationList from './ConversationList.svelte';
  import FileTree from '$lib/components/files/FileTree.svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

  let isCollapsed = false;
  let isErrorDialogOpen = false;
  let errorMessage = 'Failed to create note. Please try again.';
  let isNewNoteDialogOpen = false;
  let newNoteName = '';
  let newNoteInput: HTMLInputElement | null = null;
  let isSettingsOpen = false;
  const settingsSections = [
    { key: 'account', label: 'Account', icon: User },
    { key: 'system', label: 'System', icon: Monitor },
    { key: 'skills', label: 'Skills', icon: Wrench }
  ];
  let activeSettingsSection = 'account';

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

  async function handleNoteClick(path: string) {
    // Save current note if dirty
    if ($editorStore.isDirty && $editorStore.currentNoteId) {
      const save = confirm('Save changes before switching notes?');
      if (save) await editorStore.saveNote();
    }

    currentNoteId.set(path);
    await editorStore.loadNote('notes', path);
  }

  async function handleNewNote() {
    newNoteName = '';
    isNewNoteDialogOpen = true;
  }

  async function createNoteFromDialog() {
    const name = newNoteName.trim();
    if (!name) return;
    const filename = name.endsWith('.md') ? name : `${name}.md`;

    try {
      const response = await fetch('/api/files/content', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          basePath: 'notes',
          path: filename,
          content: `# ${name}\n\n`
        })
      });

      if (!response.ok) throw new Error('Failed to create note');
      const data = await response.json();
      const noteId = data?.id || filename;

      // Reload the files tree and open the new note
      const { filesStore } = await import('$lib/stores/files');
      await filesStore.load('notes');
      currentNoteId.set(noteId);
      await editorStore.loadNote('notes', noteId);
      isNewNoteDialogOpen = false;
    } catch (error) {
      console.error('Failed to create note:', error);
      errorMessage = 'Failed to create note. Please try again.';
      isErrorDialogOpen = true;
    }
  }

</script>

<AlertDialog.Root bind:open={isNewNoteDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      newNoteInput?.focus();
      newNoteInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Create a new note</AlertDialog.Title>
      <AlertDialog.Description>Pick a name. We'll save it as a markdown file.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="Note name"
        bind:this={newNoteInput}
        bind:value={newNoteName}
        on:keydown={(event) => {
          if (event.key === 'Enter') createNoteFromDialog();
        }}
      />
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={() => (isNewNoteDialogOpen = false)}>Cancel</AlertDialog.Cancel>
      <AlertDialog.Action
        disabled={!newNoteName.trim()}
        onclick={createNoteFromDialog}
      >
        Create note
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<AlertDialog.Root bind:open={isErrorDialogOpen}>
  <AlertDialog.Content>
    <AlertDialog.Header>
      <AlertDialog.Title>Unable to create note</AlertDialog.Title>
      <AlertDialog.Description>{errorMessage}</AlertDialog.Description>
    </AlertDialog.Header>
    <AlertDialog.Footer>
      <AlertDialog.Action
        onclick={() => (isErrorDialogOpen = false)}
      >
        OK
      </AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<AlertDialog.Root bind:open={isSettingsOpen}>
  <AlertDialog.Content class="settings-dialog">
    <AlertDialog.Header class="settings-header">
      <AlertDialog.Title>Settings</AlertDialog.Title>
      <AlertDialog.Description>Configure your workspace.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="settings-layout">
      <aside class="settings-nav">
        {#each settingsSections as section (section.key)}
          <button
            class="settings-nav-item"
            class:active={activeSettingsSection === section.key}
            on:click={() => (activeSettingsSection = section.key)}
          >
            <svelte:component this={section.icon} size={16} />
            <span>{section.label}</span>
          </button>
        {/each}
      </aside>
      <div class="settings-content">
        {#if activeSettingsSection === 'account'}
          <h3>Account</h3>
          <p>Profile, security, and billing settings will appear here.</p>
        {:else if activeSettingsSection === 'system'}
          <h3>System</h3>
          <p>Theme, notifications, and system preferences will appear here.</p>
        {:else}
          <h3>Skills</h3>
          <p>Manage installed skills and permissions here.</p>
        {/if}
      </div>
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Action onclick={() => (isSettingsOpen = false)}>Close</AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

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
      <!-- Quick Actions -->
      <div class="quick-actions">
        <button
          on:click={handleNewChat}
          class="quick-action-btn"
          aria-label="New chat"
          title="New chat"
        >
          <MessageSquare size={20} />
        </button>
        <button
          on:click={handleNewNote}
          class="quick-action-btn"
          aria-label="New note"
          title="New note"
        >
          <FileText size={20} />
        </button>
      </div>

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
            <FileTree basePath="notes" emptyMessage="No notes found" hideExtensions={true} onFileClick={handleNoteClick} />
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

    <div class="sidebar-footer">
      <button on:click={() => (isSettingsOpen = true)} class="settings-btn" aria-label="Open settings">
        <Settings size={18} />
        {#if !isCollapsed}
          <span>Settings</span>
        {/if}
      </button>
    </div>
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

  .quick-actions {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.5rem;
    margin: 1rem;
  }

  .quick-action-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.65rem;
    background-color: var(--color-sidebar-primary);
    color: var(--color-sidebar-primary-foreground);
    border: none;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: opacity 0.2s;
  }

  .quick-action-btn:hover {
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

  .sidebar-footer {
    margin-top: auto;
    padding: 0.75rem 1rem;
    border-top: 1px solid var(--color-sidebar-border);
    display: flex;
    justify-content: center;
  }

  .settings-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    padding: 0.5rem 0.75rem;
    border-radius: 0.5rem;
    font-size: 0.875rem;
    color: var(--color-sidebar-foreground);
    background-color: transparent;
    border: 1px solid var(--color-sidebar-border);
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .settings-btn:hover {
    background-color: var(--color-sidebar-accent);
    border-color: var(--color-sidebar-border);
  }

  .sidebar.collapsed .settings-btn {
    width: auto;
    justify-content: center;
    padding: 0.5rem;
  }

  .settings-layout {
    display: grid;
    grid-template-columns: 200px 1fr;
    gap: 1.5rem;
    min-height: 420px;
    padding: 0.75rem 0 0;
  }

  .settings-nav {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    border-right: 1px solid var(--color-border);
    padding-right: 0.75rem;
  }

  .settings-nav-item {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.45rem 0.6rem;
    border-radius: 0.5rem;
    background: transparent;
    border: none;
    color: var(--color-muted-foreground);
    font-size: 0.85rem;
    cursor: pointer;
    text-align: left;
    transition: background-color 0.2s ease, color 0.2s ease;
  }

  .settings-nav-item:hover {
    background-color: var(--color-sidebar-accent);
    color: var(--color-foreground);
  }

  .settings-nav-item.active {
    background-color: var(--color-sidebar-accent);
    color: var(--color-foreground);
    font-weight: 600;
  }

  .settings-content h3 {
    margin: 0 0 0.35rem 0;
    font-size: 1rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .settings-content p {
    margin: 0;
    color: var(--color-muted-foreground);
    font-size: 0.85rem;
    line-height: 1.5;
  }

  .settings-dialog {
    max-width: 860px;
    width: min(92vw, 860px);
    max-height: min(85vh, 680px);
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  .settings-header {
    border-bottom: 1px solid var(--color-border);
    padding-bottom: 0.75rem;
  }

  .settings-layout {
    flex: 1;
    overflow: hidden;
  }

  .settings-nav {
    overflow-y: auto;
  }

  .settings-content {
    overflow-y: auto;
    padding-right: 0.5rem;
  }

</style>
