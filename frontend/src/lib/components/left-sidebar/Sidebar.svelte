<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Plus, Folder } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import { filesStore } from '$lib/stores/files';
  import { websitesStore } from '$lib/stores/websites';
  import ConversationList from './ConversationList.svelte';
  import NotesPanel from '$lib/components/left-sidebar/NotesPanel.svelte';
  import FilesPanel from '$lib/components/left-sidebar/FilesPanel.svelte';
  import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';
  import SettingsDialogContainer from '$lib/components/left-sidebar/panels/SettingsDialogContainer.svelte';
  import { useSidebarSectionLoader, type SidebarSection } from '$lib/hooks/useSidebarSectionLoader';
  import SidebarRail from '$lib/components/left-sidebar/SidebarRail.svelte';
  import SidebarSectionHeader from '$lib/components/left-sidebar/SidebarSectionHeader.svelte';
  import NewNoteDialog from '$lib/components/left-sidebar/dialogs/NewNoteDialog.svelte';
  import NewFolderDialog from '$lib/components/left-sidebar/dialogs/NewFolderDialog.svelte';
  import NewWorkspaceFolderDialog from '$lib/components/left-sidebar/dialogs/NewWorkspaceFolderDialog.svelte';
  import NewWebsiteDialog from '$lib/components/left-sidebar/dialogs/NewWebsiteDialog.svelte';
  import SaveChangesDialog from '$lib/components/left-sidebar/dialogs/SaveChangesDialog.svelte';
  import SidebarErrorDialog from '$lib/components/left-sidebar/dialogs/SidebarErrorDialog.svelte';
  import { dispatchCacheEvent } from '$lib/utils/cacheEvents';
  import { Button } from '$lib/components/ui/button';

  let isCollapsed = false;
  let isErrorDialogOpen = false;
  let errorMessage = 'Failed to create note. Please try again.';
  let isNewNoteDialogOpen = false;
  let newNoteName = '';
  let isNewFolderDialogOpen = false;
  let newFolderName = '';
  let isNewWorkspaceFolderDialogOpen = false;
  let newWorkspaceFolderName = '';
  let isSettingsOpen = false;
  let isNewWebsiteDialogOpen = false;
  let newWebsiteUrl = '';
  let isSavingWebsite = false;
  let isCreatingWorkspaceFolder = false;
  let isCreatingNote = false;
  let isCreatingFolder = false;
  let isSaveChangesDialogOpen = false;
  let pendingNotePath: string | null = null;
  let settingsDialog: { handleProfileImageError: () => void } | null = null;
  let profileImageSrc = '';
  const sidebarLogoSrc = '/images/logo.svg';
  let isMounted = false;
  const { loadSectionData } = useSidebarSectionLoader();

  onMount(() => {
    // Mark as mounted to enable reactive data loading
    isMounted = true;

    if (typeof window !== 'undefined') {
      window.addEventListener('keydown', handleSectionShortcut);
    }
  });

  onDestroy(() => {
    // Clean up event listener
    if (typeof window !== 'undefined') {
      window.removeEventListener('keydown', handleSectionShortcut);
    }
  });

  function handleSectionShortcut(event: KeyboardEvent) {
    const isModifier = event.metaKey || event.ctrlKey;
    if (!isModifier || event.shiftKey || event.altKey) {
      return;
    }

    if (event.key === '1') {
      event.preventDefault();
      openSection('notes');
    } else if (event.key === '2') {
      event.preventDefault();
      openSection('websites');
    } else if (event.key === '3') {
      event.preventDefault();
      openSection('workspace');
    } else if (event.key === '4') {
      event.preventDefault();
      openSection('history');
    }
  }

  async function handleNewChat() {
    await chatStore.clear();
    await conversationListStore.refresh();
  }

  function toggleSidebar() {
    isCollapsed = !isCollapsed;
  }

  let activeSection: SidebarSection = 'notes';

  function openSection(section: SidebarSection) {
    activeSection = section;
    isCollapsed = false;
  }

  // Lazy load section data when switching sections (only after mount to ensure stores are ready)
  $: if (isMounted && activeSection) {
    loadSectionData(activeSection);
  }

  async function handleNoteClick(path: string) {
    // Check if current note has unsaved changes
    if ($editorStore.isDirty && $editorStore.currentNoteId) {
      pendingNotePath = path;
      isSaveChangesDialogOpen = true;
      return;
    }

    // Load the new note
    websitesStore.clearActive();
    currentNoteId.set(path);
    await editorStore.loadNote('notes', path, { source: 'user' });
  }

  async function confirmSaveAndSwitch() {
    if ($editorStore.currentNoteId) {
      await editorStore.saveNote();
    }
    isSaveChangesDialogOpen = false;
    if (pendingNotePath) {
      websitesStore.clearActive();
      currentNoteId.set(pendingNotePath);
      await editorStore.loadNote('notes', pendingNotePath, { source: 'user' });
      pendingNotePath = null;
    }
  }

  async function discardAndSwitch() {
    isSaveChangesDialogOpen = false;
    if (pendingNotePath) {
      websitesStore.clearActive();
      currentNoteId.set(pendingNotePath);
      await editorStore.loadNote('notes', pendingNotePath, { source: 'user' });
      pendingNotePath = null;
    }
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

  function handleNewWorkspaceFolder() {
    newWorkspaceFolderName = '';
    isNewWorkspaceFolderDialogOpen = true;
  }

  function handleNewWebsite() {
    newWebsiteUrl = '';
    isNewWebsiteDialogOpen = true;
  }

  async function saveWebsiteFromDialog() {
    const url = newWebsiteUrl.trim();
    if (!url || isSavingWebsite) return;

    isSavingWebsite = true;
    try {
      const response = await fetch('/api/websites/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url })
      });

      const data = await response.json();
      if (!response.ok) {
        const detail = data?.error;
        const message = typeof detail === 'string' ? detail : detail?.message;
        throw new Error(message || 'Failed to save website');
      }

      const websiteId = data?.data?.id;

      await websitesStore.load(true);
      dispatchCacheEvent('website.saved');
      if (websiteId) {
        await websitesStore.loadById(websiteId);
      }
      isNewWebsiteDialogOpen = false;
    } catch (error) {
      console.error('Failed to save website:', error);
      errorMessage =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to save website. Please try again.';
      isErrorDialogOpen = true;
    } finally {
      isSavingWebsite = false;
    }
  }

  async function createNoteFromDialog() {
    const name = newNoteName.trim();
    if (!name || isCreatingNote) return;
    const filename = name.endsWith('.md') ? name : `${name}.md`;

    isCreatingNote = true;
    try {
      const response = await fetch('/api/notes', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          path: filename,
          content: `# ${name}\n\n`
        })
      });

      if (!response.ok) throw new Error('Failed to create note');
      const data = await response.json();
      const noteId = data?.id || filename;

      const folder = filename.includes('/') ? filename.split('/').slice(0, -1).join('/') : '';
      filesStore.addNoteNode?.({
        id: noteId,
        name: filename,
        folder,
        modified: data?.modified
      });
      dispatchCacheEvent('note.created');
      currentNoteId.set(noteId);
      await editorStore.loadNote('notes', noteId, { source: 'user' });
      isNewNoteDialogOpen = false;
    } catch (error) {
      console.error('Failed to create note:', error);
      errorMessage = 'Failed to create note. Please try again.';
      isErrorDialogOpen = true;
    } finally {
      isCreatingNote = false;
    }
  }

  async function createFolderFromDialog() {
    const name = newFolderName.trim().replace(/^\/+|\/+$/g, '');
    if (!name || isCreatingFolder) return;

    isCreatingFolder = true;
    try {
      const response = await fetch('/api/notes/folders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: name })
      });

      if (!response.ok) throw new Error('Failed to create folder');
      await filesStore.load('notes', true);
      dispatchCacheEvent('note.created');
      isNewFolderDialogOpen = false;
    } catch (error) {
      console.error('Failed to create folder:', error);
      errorMessage = 'Failed to create folder. Please try again.';
      isErrorDialogOpen = true;
    } finally {
      isCreatingFolder = false;
    }
  }

  async function createWorkspaceFolderFromDialog() {
    const name = newWorkspaceFolderName.trim().replace(/^\/+|\/+$/g, '');
    if (!name || isCreatingWorkspaceFolder) return;

    isCreatingWorkspaceFolder = true;
    try {
      const response = await fetch('/api/files/folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ basePath: '.', path: name })
      });

      if (!response.ok) throw new Error('Failed to create folder');
      await filesStore.load('.', true);
      dispatchCacheEvent('file.uploaded');
      isNewWorkspaceFolderDialogOpen = false;
    } catch (error) {
      console.error('Failed to create folder:', error);
      errorMessage = 'Failed to create folder. Please try again.';
      isErrorDialogOpen = true;
    } finally {
      isCreatingWorkspaceFolder = false;
    }
  }

</script>

<NewNoteDialog
  bind:open={isNewNoteDialogOpen}
  bind:value={newNoteName}
  isBusy={isCreatingNote}
  onConfirm={createNoteFromDialog}
  onCancel={() => (isNewNoteDialogOpen = false)}
/>

<NewFolderDialog
  bind:open={isNewFolderDialogOpen}
  bind:value={newFolderName}
  isBusy={isCreatingFolder}
  onConfirm={createFolderFromDialog}
  onCancel={() => (isNewFolderDialogOpen = false)}
/>

<NewWorkspaceFolderDialog
  bind:open={isNewWorkspaceFolderDialogOpen}
  bind:value={newWorkspaceFolderName}
  isBusy={isCreatingWorkspaceFolder}
  onConfirm={createWorkspaceFolderFromDialog}
  onCancel={() => (isNewWorkspaceFolderDialogOpen = false)}
/>

<NewWebsiteDialog
  bind:open={isNewWebsiteDialogOpen}
  bind:value={newWebsiteUrl}
  isBusy={isSavingWebsite}
  onConfirm={saveWebsiteFromDialog}
  onCancel={() => (isNewWebsiteDialogOpen = false)}
/>

<SidebarErrorDialog
  bind:open={isErrorDialogOpen}
  message={errorMessage}
  onConfirm={() => (isErrorDialogOpen = false)}
/>

<SaveChangesDialog
  bind:open={isSaveChangesDialogOpen}
  onConfirm={confirmSaveAndSwitch}
  onCancel={discardAndSwitch}
/>

<SettingsDialogContainer
  bind:open={isSettingsOpen}
  bind:profileImageSrc
  bind:this={settingsDialog}
/>

<div class="sidebar-shell" class:collapsed={isCollapsed}>
  <SidebarRail
    {isCollapsed}
    {profileImageSrc}
    {sidebarLogoSrc}
    onToggle={toggleSidebar}
    onOpenSection={openSection}
    onOpenSettings={() => (isSettingsOpen = true)}
    onProfileImageError={() => settingsDialog?.handleProfileImageError()}
  />

  <div class="sidebar-panel" aria-hidden={isCollapsed}>
    <div class="panel-body">
      <!-- Notes Section -->
      <div class="panel-section" class:hidden={activeSection !== 'notes'}>
        <SidebarSectionHeader
          title="Notes"
          searchPlaceholder="Search notes..."
          onSearch={(query) => filesStore.searchNotes(query)}
          onClear={() => filesStore.load('notes', true)}
        >
          <svelte:fragment slot="actions">
            <Button
              size="icon"
              variant="ghost"
              class="panel-action"
              onclick={handleNewFolder}
              aria-label="New folder"
              title="New folder"
            >
              <Folder size={16} />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              class="panel-action"
              onclick={handleNewNote}
              aria-label="New note"
              title="New note"
            >
              <Plus size={16} />
            </Button>
          </svelte:fragment>
        </SidebarSectionHeader>
        <div class="notes-content">
          <NotesPanel basePath="notes" emptyMessage="No notes found" hideExtensions={true} onFileClick={handleNoteClick} />
        </div>
      </div>

      <!-- Websites Section -->
      <div class="panel-section" class:hidden={activeSection !== 'websites'}>
        <SidebarSectionHeader
          title="Websites"
          searchPlaceholder="Search websites..."
          onSearch={(query) => websitesStore.search(query)}
          onClear={() => websitesStore.load(true)}
        >
          <svelte:fragment slot="actions">
            <Button
              size="icon"
              variant="ghost"
              class="panel-action"
              onclick={handleNewWebsite}
              aria-label="Save website"
              title="Save website"
            >
              <Plus size={16} />
            </Button>
          </svelte:fragment>
        </SidebarSectionHeader>
        <div class="files-content">
          <WebsitesPanel />
        </div>
      </div>

      <!-- Workspace Section -->
      <div class="panel-section" class:hidden={activeSection !== 'workspace'}>
        <SidebarSectionHeader
          title="Files"
          searchPlaceholder="Search files..."
          onSearch={(query) => filesStore.searchFiles('.', query)}
          onClear={() => filesStore.load('.', true)}
        >
          <svelte:fragment slot="actions">
            <Button
              size="icon"
              variant="ghost"
              class="panel-action"
              onclick={handleNewWorkspaceFolder}
              aria-label="New folder"
              title="New folder"
            >
              <Folder size={16} />
            </Button>
          </svelte:fragment>
        </SidebarSectionHeader>
        <div class="files-content">
          <FilesPanel />
        </div>
      </div>

      <!-- History Section -->
      <div class="panel-section" class:hidden={activeSection !== 'history'}>
        <SidebarSectionHeader
          title="Chat"
          searchPlaceholder="Search conversations..."
          onSearch={(query) => conversationListStore.search(query)}
          onClear={() => conversationListStore.load(true)}
        />
        <div class="history-content">
          <ConversationList />
        </div>
      </div>
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

  .panel-section.hidden {
    display: none;
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



</style>
