<script lang="ts">
  import { onMount } from 'svelte';
  import { ChevronRight, MessageSquare, FileText, Globe, Settings, User, Monitor, Wrench, Menu, Plus, Folder } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import { websitesStore } from '$lib/stores/websites';
  import SearchBar from './SearchBar.svelte';
  import ConversationList from './ConversationList.svelte';
  import NotesPanel from '$lib/components/history/NotesPanel.svelte';
  import WebsitesList from '$lib/components/websites/WebsitesList.svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

  let isCollapsed = false;
  let isErrorDialogOpen = false;
  let errorMessage = 'Failed to create note. Please try again.';
  let isNewNoteDialogOpen = false;
  let newNoteName = '';
  let newNoteInput: HTMLInputElement | null = null;
  let isNewFolderDialogOpen = false;
  let newFolderName = '';
  let newFolderInput: HTMLInputElement | null = null;
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

  let activeSection: 'history' | 'notes' | 'websites' = 'history';

  function openSection(section: typeof activeSection) {
    activeSection = section;
    isCollapsed = false;
  }

  async function handleNoteClick(path: string) {
    // Save current note if dirty
    if ($editorStore.isDirty && $editorStore.currentNoteId) {
      const save = confirm('Save changes before switching notes?');
      if (save) await editorStore.saveNote();
    }

    websitesStore.clearActive();
    currentNoteId.set(path);
    await editorStore.loadNote('notes', path);
  }

  async function handleNewNote() {
    websitesStore.clearActive();
    newNoteName = '';
    isNewNoteDialogOpen = true;
  }

  function handleNewFolder() {
    websitesStore.clearActive();
    newFolderName = '';
    isNewFolderDialogOpen = true;
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

  async function createFolderFromDialog() {
    const name = newFolderName.trim().replace(/^\/+|\/+$/g, '');
    if (!name) return;

    try {
      const response = await fetch('/api/files/folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          basePath: 'notes',
          path: name
        })
      });

      if (!response.ok) throw new Error('Failed to create folder');
      const { filesStore } = await import('$lib/stores/files');
      await filesStore.load('notes');
      isNewFolderDialogOpen = false;
    } catch (error) {
      console.error('Failed to create folder:', error);
      errorMessage = 'Failed to create folder. Please try again.';
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

<AlertDialog.Root bind:open={isNewFolderDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      newFolderInput?.focus();
      newFolderInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Create a new folder</AlertDialog.Title>
      <AlertDialog.Description>Folders help organize your notes.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="Folder name"
        bind:this={newFolderInput}
        bind:value={newFolderName}
        on:keydown={(event) => {
          if (event.key === 'Enter') createFolderFromDialog();
        }}
      />
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Cancel onclick={() => (isNewFolderDialogOpen = false)}>Cancel</AlertDialog.Cancel>
      <AlertDialog.Action
        disabled={!newFolderName.trim()}
        onclick={createFolderFromDialog}
      >
        Create folder
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

<div class="sidebar-shell" class:collapsed={isCollapsed}>
  <div class="sidebar-rail">
    <button
      class="rail-toggle"
      on:click={toggleSidebar}
      aria-label={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
      title={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
    >
      <Menu size={20} />
    </button>

    <div class="rail-actions">
      <button
        on:click={() => openSection('history')}
        class="rail-btn"
        aria-label="History"
        title="History"
      >
        <MessageSquare size={18} />
      </button>
      <button
        on:click={() => openSection('notes')}
        class="rail-btn"
        aria-label="Notes"
        title="Notes"
      >
        <FileText size={18} />
      </button>
      <button
        on:click={() => openSection('websites')}
        class="rail-btn"
        aria-label="Websites"
        title="Websites"
      >
        <Globe size={18} />
      </button>
    </div>

    <div class="rail-footer">
      <button
        on:click={() => (isSettingsOpen = true)}
        class="rail-btn"
        aria-label="Open settings"
        title="Settings"
      >
        <Settings size={18} />
      </button>
    </div>
  </div>

  <div class="sidebar-panel" aria-hidden={isCollapsed}>
    <div class="panel-body">
      {#if activeSection === 'history'}
        <div class="panel-section">
          <div class="panel-section-header">
            <div class="panel-section-header-row">
              <div class="panel-section-title">History</div>
              <div class="panel-section-actions"></div>
            </div>
            <SearchBar />
          </div>
          <div class="history-content">
            <ConversationList />
          </div>
        </div>
      {:else if activeSection === 'notes'}
        <div class="panel-section">
          <div class="panel-section-header">
            <div class="panel-section-header-row">
              <div class="panel-section-title">Notes</div>
              <div class="panel-section-actions">
                <button class="panel-action" on:click={handleNewFolder} aria-label="New folder" title="New folder">
                  <Folder size={16} />
                </button>
                <button class="panel-action" on:click={handleNewNote} aria-label="New note" title="New note">
                  <Plus size={16} />
                </button>
              </div>
            </div>
            <SearchBar />
          </div>
          <div class="notes-content">
            <NotesPanel basePath="notes" emptyMessage="No notes found" hideExtensions={true} onFileClick={handleNoteClick} />
          </div>
        </div>
      {:else}
        <div class="panel-section">
          <div class="panel-section-header">
            <div class="panel-section-header-row">
              <div class="panel-section-title">Websites</div>
              <div class="panel-section-actions"></div>
            </div>
            <SearchBar />
          </div>
          <div class="files-content">
            <WebsitesList />
          </div>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .sidebar-shell {
    display: flex;
    height: 100vh;
    background-color: var(--color-sidebar);
    border-right: 1px solid var(--color-sidebar-border);
  }

  .sidebar-rail {
    width: 56px;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 0.75rem 0.5rem;
    border-right: 1px solid var(--color-sidebar-border);
    background-color: var(--color-sidebar);
    gap: 0.75rem;
  }

  .rail-toggle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: 0.5rem;
    border: 1px solid var(--color-sidebar-border);
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .rail-toggle:hover {
    background-color: var(--color-sidebar-accent);
  }

  .rail-actions {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    align-items: center;
    flex: 1;
    width: 100%;
  }

  .rail-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: 0.5rem;
    border: 1px solid transparent;
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .rail-btn:hover {
    background-color: var(--color-sidebar-accent);
  }

  .rail-footer {
    display: flex;
    justify-content: center;
  }

  .sidebar-panel {
    width: 280px;
    display: flex;
    flex-direction: column;
    background-color: var(--color-sidebar);
    transition: width 0.2s ease, opacity 0.2s ease;
    overflow: hidden;
  }

  .sidebar-shell.collapsed .sidebar-panel {
    width: 0;
    opacity: 0;
    pointer-events: none;
  }

  .panel-body {
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow: hidden;
  }

  .panel-section {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0;
  }

  .panel-section-header {
    display: flex;
    flex-direction: column;
    padding: 1rem;
    gap: 0.75rem;
    border-bottom: 1px solid var(--color-sidebar-border);
  }

  .panel-section-header-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .panel-section-title {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-weight: 600;
    font-size: 0.95rem;
    color: var(--color-sidebar-foreground);
  }

  .panel-section-actions {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
  }

  .panel-action {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.25rem;
    border-radius: 0.5rem;
    border: 1px solid transparent;
    background-color: transparent;
    color: var(--color-sidebar-foreground);
    font-size: 0.75rem;
    cursor: pointer;
    transition: background-color 0.2s ease, border-color 0.2s ease;
  }

  .panel-action:hover {
    background-color: var(--color-sidebar-accent);
  }

  .history-content {
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow-y: auto;
  }

  .notes-content {
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow-y: auto;
  }

  .files-content {
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow-y: auto;
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
