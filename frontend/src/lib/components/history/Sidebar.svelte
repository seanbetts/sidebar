<script lang="ts">
  import { onMount } from 'svelte';
  import { MessageSquare, FileText, Globe, Settings, User, Monitor, Wrench, Menu, Plus, Folder, Loader2 } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import { websitesStore } from '$lib/stores/websites';
  import SearchBar from './SearchBar.svelte';
  import ConversationList from './ConversationList.svelte';
  import NotesPanel from '$lib/components/history/NotesPanel.svelte';
  import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';
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
  let isNewWebsiteDialogOpen = false;
  let newWebsiteUrl = '';
  let newWebsiteInput: HTMLInputElement | null = null;
  let isSavingWebsite = false;
  let communicationStyle = '';
  let workingRelationship = '';
  let name = '';
  let jobTitle = '';
  let employer = '';
  let dateOfBirth = '';
  let gender = '';
  let pronouns = '';
  let location = '';
  let initialCommunicationStyle = '';
  let initialWorkingRelationship = '';
  let initialName = '';
  let initialJobTitle = '';
  let initialEmployer = '';
  let initialDateOfBirth = '';
  let initialGender = '';
  let initialPronouns = '';
  let initialLocation = '';
  let isLoadingSettings = false;
  let isSavingSettings = false;
  let settingsLoaded = false;
  let settingsError = '';
  let locationSuggestions: Array<{ description: string; place_id: string }> = [];
  let isLoadingLocations = false;
  let locationLookupError = '';
  let locationLookupTimer: ReturnType<typeof setTimeout> | null = null;
  let activeLocationIndex = -1;
  let lastSelectedLocation = '';
  let autosaveTimer: ReturnType<typeof setTimeout> | null = null;
  let wasSettingsOpen = false;
  let settingsDirty = false;
  const pronounOptions = [
    'he/him',
    'she/her',
    'they/them',
    'he/they',
    'she/they',
    'they/he',
    'they/she',
    'other'
  ];
  const settingsSections = [
    { key: 'account', label: 'Account', icon: User },
    { key: 'system', label: 'System', icon: Monitor },
    { key: 'skills', label: 'Skills', icon: Wrench }
  ];
  let activeSettingsSection = 'account';

  onMount(() => {
    conversationListStore.load();
  });

  async function loadSettings(force = false) {
    if (isLoadingSettings || (settingsLoaded && !force)) return;
    isLoadingSettings = true;
    settingsError = '';

    try {
      const response = await fetch('/api/settings');
      if (!response.ok) {
        throw new Error('Failed to load settings');
      }
      const data = await response.json();
      communicationStyle = data?.communication_style ?? '';
      workingRelationship = data?.working_relationship ?? '';
      name = data?.name ?? '';
      jobTitle = data?.job_title ?? '';
      employer = data?.employer ?? '';
      dateOfBirth = data?.date_of_birth ?? '';
      gender = data?.gender ?? '';
      pronouns = data?.pronouns ?? '';
      location = data?.location ?? '';
      initialCommunicationStyle = communicationStyle;
      initialWorkingRelationship = workingRelationship;
      initialName = name;
      initialJobTitle = jobTitle;
      initialEmployer = employer;
      initialDateOfBirth = dateOfBirth;
      initialGender = gender;
      initialPronouns = pronouns;
      initialLocation = location;
      settingsLoaded = true;
    } catch (error) {
      settingsError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to load settings.';
    } finally {
      isLoadingSettings = false;
    }
  }

  async function saveSettings() {
    if (isSavingSettings) return;
    isSavingSettings = true;
    settingsError = '';

    try {
      const response = await fetch('/api/settings', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          communication_style: communicationStyle,
          working_relationship: workingRelationship,
          name,
          job_title: jobTitle,
          employer,
          date_of_birth: dateOfBirth || null,
          gender,
          pronouns,
          location
        })
      });

      if (!response.ok) {
        throw new Error('Failed to save settings');
      }

      const data = await response.json();
      communicationStyle = data?.communication_style ?? '';
      workingRelationship = data?.working_relationship ?? '';
      name = data?.name ?? '';
      jobTitle = data?.job_title ?? '';
      employer = data?.employer ?? '';
      dateOfBirth = data?.date_of_birth ?? '';
      gender = data?.gender ?? '';
      pronouns = data?.pronouns ?? '';
      location = data?.location ?? '';
      initialCommunicationStyle = communicationStyle;
      initialWorkingRelationship = workingRelationship;
      initialName = name;
      initialJobTitle = jobTitle;
      initialEmployer = employer;
      initialDateOfBirth = dateOfBirth;
      initialGender = gender;
      initialPronouns = pronouns;
      initialLocation = location;
    } catch (error) {
      settingsError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to save settings.';
    } finally {
      isSavingSettings = false;
    }
  }

  function resetSettings() {
    communicationStyle = initialCommunicationStyle;
    workingRelationship = initialWorkingRelationship;
    name = initialName;
    jobTitle = initialJobTitle;
    employer = initialEmployer;
    dateOfBirth = initialDateOfBirth;
    gender = initialGender;
    pronouns = initialPronouns;
    location = initialLocation;
    settingsError = '';
  }

  async function handleNewChat() {
    await chatStore.clear();
    await conversationListStore.refresh();
  }

  function toggleSidebar() {
    isCollapsed = !isCollapsed;
  }

  let activeSection: 'history' | 'notes' | 'websites' = 'notes';

  function openSection(section: typeof activeSection) {
    activeSection = section;
    isCollapsed = false;
  }

  $: if (isSettingsOpen && !settingsLoaded) {
    loadSettings();
  }

  function selectLocation(value: string) {
    location = value;
    locationSuggestions = [];
    locationLookupError = '';
    if (locationLookupTimer) clearTimeout(locationLookupTimer);
    activeLocationIndex = -1;
    lastSelectedLocation = value.trim();
  }

  async function searchLocations(value: string) {
    const query = value.trim();
    if (query.length < 2) {
      locationSuggestions = [];
      locationLookupError = '';
      activeLocationIndex = -1;
      return;
    }

    isLoadingLocations = true;
    locationLookupError = '';
    try {
      const response = await fetch(`/api/places/autocomplete?input=${encodeURIComponent(query)}`);
      if (!response.ok) {
        throw new Error('Failed to load locations');
      }
      const data = await response.json();
      locationSuggestions = Array.isArray(data?.predictions) ? data.predictions : [];
      activeLocationIndex = locationSuggestions.length ? 0 : -1;
    } catch (error) {
      console.error('Failed to load locations:', error);
      locationLookupError = 'Unable to load locations.';
    } finally {
      isLoadingLocations = false;
    }
  }

  function handleLocationInput() {
    if (location.trim() === lastSelectedLocation) {
      locationSuggestions = [];
      locationLookupError = '';
      activeLocationIndex = -1;
      return;
    }
    if (locationLookupTimer) clearTimeout(locationLookupTimer);
    locationLookupTimer = setTimeout(() => {
      searchLocations(location);
    }, 300);
  }

  function handleLocationKeydown(event: KeyboardEvent) {
    if (!locationSuggestions.length) return;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      activeLocationIndex = Math.min(activeLocationIndex + 1, locationSuggestions.length - 1);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      activeLocationIndex = Math.max(activeLocationIndex - 1, 0);
    } else if (event.key === 'Enter') {
      event.preventDefault();
      if (activeLocationIndex >= 0) {
        selectLocation(locationSuggestions[activeLocationIndex].description);
      }
    } else if (event.key === 'Escape') {
      locationSuggestions = [];
      activeLocationIndex = -1;
    }
  }

  function handleLocationBlur() {
    setTimeout(() => {
      locationSuggestions = [];
      activeLocationIndex = -1;
    }, 150);
  }

  function scheduleAutosave() {
    if (autosaveTimer) clearTimeout(autosaveTimer);
    autosaveTimer = setTimeout(() => {
      saveSettings();
    }, 800);
  }

  async function handleSettingsClose() {
    if (settingsDirty) {
      await saveSettings();
    }
    settingsLoaded = false;
    settingsError = '';
    locationSuggestions = [];
  }

  $: settingsDirty =
    settingsLoaded &&
    (communicationStyle !== initialCommunicationStyle ||
      workingRelationship !== initialWorkingRelationship ||
      name !== initialName ||
      jobTitle !== initialJobTitle ||
      employer !== initialEmployer ||
      dateOfBirth !== initialDateOfBirth ||
      gender !== initialGender ||
      pronouns !== initialPronouns ||
      location !== initialLocation);

  $: if (settingsLoaded && isSettingsOpen && settingsDirty) {
    scheduleAutosave();
  }

  $: if (wasSettingsOpen && !isSettingsOpen) {
    handleSettingsClose();
  }

  $: wasSettingsOpen = isSettingsOpen;

  async function handleNoteClick(path: string) {
    // Save current note if dirty
    if ($editorStore.isDirty && $editorStore.currentNoteId) {
      const save = confirm('Save changes before switching notes?');
      if (save) await editorStore.saveNote();
    }

    websitesStore.clearActive();
    currentNoteId.set(path);
    await editorStore.loadNote('notes', path, { source: 'user' });
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

      await websitesStore.load();
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
    if (!name) return;
    const filename = name.endsWith('.md') ? name : `${name}.md`;

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

      // Reload the files tree and open the new note
      const { filesStore } = await import('$lib/stores/files');
      await filesStore.load('notes');
      currentNoteId.set(noteId);
      await editorStore.loadNote('notes', noteId, { source: 'user' });
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
      const response = await fetch('/api/notes/folders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: name })
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

<AlertDialog.Root bind:open={isNewWebsiteDialogOpen}>
  <AlertDialog.Content
    onOpenAutoFocus={(event) => {
      event.preventDefault();
      newWebsiteInput?.focus();
      newWebsiteInput?.select();
    }}
  >
    <AlertDialog.Header>
      <AlertDialog.Title>Save a website</AlertDialog.Title>
      <AlertDialog.Description>Paste a URL to save it to your archive.</AlertDialog.Description>
    </AlertDialog.Header>
    <div class="py-2">
      <input
        class="w-full rounded-md border bg-background px-3 py-2 text-sm shadow-sm outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        type="text"
        placeholder="https://example.com"
        bind:this={newWebsiteInput}
        bind:value={newWebsiteUrl}
        disabled={isSavingWebsite}
        on:keydown={(event) => {
          if (event.key === 'Enter') saveWebsiteFromDialog();
        }}
      />
    </div>
    <AlertDialog.Footer>
      <AlertDialog.Cancel
        disabled={isSavingWebsite}
        onclick={() => (isNewWebsiteDialogOpen = false)}
      >
        Cancel
      </AlertDialog.Cancel>
      <AlertDialog.Action
        disabled={!newWebsiteUrl.trim() || isSavingWebsite}
        onclick={saveWebsiteFromDialog}
      >
        {#if isSavingWebsite}
          <span class="inline-flex items-center gap-2">
            <Loader2 size={14} class="animate-spin" />
            Saving...
          </span>
        {:else}
          Save website
        {/if}
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
  <AlertDialog.Content class="settings-dialog !max-w-[1200px] !w-[96vw]">
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
          <p>Basic details used to personalise prompts.</p>
          <div class="settings-form settings-grid">
            <label class="settings-label">
              <span>Name</span>
              <input class="settings-input" type="text" bind:value={name} placeholder="Name" />
            </label>
            <label class="settings-label">
              <span>Job title</span>
              <input class="settings-input" type="text" bind:value={jobTitle} placeholder="Job title" />
            </label>
            <label class="settings-label">
              <span>Employer</span>
              <input class="settings-input" type="text" bind:value={employer} placeholder="Employer" />
            </label>
            <label class="settings-label">
              <span>Date of birth</span>
              <input class="settings-input" type="date" bind:value={dateOfBirth} />
            </label>
            <label class="settings-label">
              <span>Gender</span>
              <input class="settings-input" type="text" bind:value={gender} placeholder="Gender" />
            </label>
            <label class="settings-label">
              <span>Pronouns</span>
              <select class="settings-input" bind:value={pronouns}>
                <option value="">Select pronouns</option>
                {#each pronounOptions as option}
                  <option value={option}>{option}</option>
                {/each}
              </select>
            </label>
            <label class="settings-label">
              <span>Location</span>
              <div class="settings-autocomplete">
                <input
                  class="settings-input"
                  type="text"
                  bind:value={location}
                  placeholder="City, country"
                  on:input={handleLocationInput}
                  on:focus={handleLocationInput}
                  on:keydown={handleLocationKeydown}
                  on:blur={handleLocationBlur}
                />
                {#if isLoadingLocations}
                  <div class="settings-suggestions">
                    <div class="settings-suggestion muted">Loading...</div>
                  </div>
                {:else if locationLookupError}
                  <div class="settings-suggestions">
                    <div class="settings-suggestion muted">{locationLookupError}</div>
                  </div>
                {:else if locationSuggestions.length}
                  <div class="settings-suggestions">
                    {#each locationSuggestions as suggestion, index}
                      <button
                        class="settings-suggestion"
                        class:active={index === activeLocationIndex}
                        type="button"
                        on:mouseenter={() => (activeLocationIndex = index)}
                        on:click={() => selectLocation(suggestion.description)}
                      >
                        {suggestion.description}
                      </button>
                    {/each}
                  </div>
                {/if}
              </div>
            </label>
          </div>
          <div class="settings-actions">
            {#if isLoadingSettings}
              <div class="settings-meta">
                <Loader2 size={16} class="spin" />
                Loading...
              </div>
            {/if}
            {#if settingsError}
              <div class="settings-error">{settingsError}</div>
            {/if}
          </div>
        {:else if activeSettingsSection === 'system'}
          <h3>System</h3>
          <p>Customize the prompts that guide your assistant.</p>
          <div class="settings-form">
            <label class="settings-label">
              <span>Communication style</span>
              <textarea
                class="settings-textarea"
                bind:value={communicationStyle}
                placeholder="Style, tone, and formatting rules."
                rows="8"
              ></textarea>
            </label>
            <label class="settings-label">
              <span>Working relationship</span>
              <textarea
                class="settings-textarea"
                bind:value={workingRelationship}
                placeholder="How the assistant should challenge and collaborate with you."
                rows="8"
              ></textarea>
            </label>
            <div class="settings-actions">
              {#if isLoadingSettings}
                <div class="settings-meta">
                  <Loader2 size={16} class="spin" />
                  Loading...
                </div>
              {/if}
            </div>
            {#if settingsError}
              <div class="settings-error">{settingsError}</div>
            {/if}
          </div>
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
      <button
        on:click={() => openSection('history')}
        class="rail-btn"
        aria-label="Chat"
        title="Chat"
      >
        <MessageSquare size={18} />
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
      {#if activeSection === 'notes'}
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
      {:else if activeSection === 'websites'}
        <div class="panel-section">
          <div class="panel-section-header">
            <div class="panel-section-header-row">
              <div class="panel-section-title">Websites</div>
              <div class="panel-section-actions">
                <button class="panel-action" on:click={handleNewWebsite} aria-label="Save website" title="Save website">
                  <Plus size={16} />
                </button>
              </div>
            </div>
            <SearchBar />
          </div>
          <div class="files-content">
            <WebsitesPanel />
          </div>
        </div>
      {:else}
        <div class="panel-section">
          <div class="panel-section-header">
            <div class="panel-section-header-row">
              <div class="panel-section-title">Chat</div>
              <div class="panel-section-actions"></div>
            </div>
            <SearchBar />
          </div>
          <div class="history-content">
            <ConversationList />
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

  .settings-form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    margin-top: 1.25rem;
  }

  .settings-label {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    color: var(--color-foreground);
    font-size: 0.85rem;
    font-weight: 600;
  }

  .settings-textarea {
    width: 100%;
    min-height: 120px;
    padding: 0.65rem 0.75rem;
    border-radius: 0.6rem;
    border: 1px solid var(--color-border);
    background: var(--color-surface);
    color: var(--color-foreground);
    font-size: 0.85rem;
    line-height: 1.5;
    resize: vertical;
  }

  .settings-input {
    width: 100%;
    padding: 0.55rem 0.75rem;
    border-radius: 0.6rem;
    border: 1px solid var(--color-border);
    background: var(--color-surface);
    color: var(--color-foreground);
    font-size: 0.85rem;
    line-height: 1.4;
  }

  .settings-textarea:focus {
    outline: 2px solid rgba(94, 140, 255, 0.35);
    border-color: rgba(94, 140, 255, 0.45);
  }

  .settings-input:focus {
    outline: 2px solid rgba(94, 140, 255, 0.35);
    border-color: rgba(94, 140, 255, 0.45);
  }

  .settings-actions {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    flex-wrap: wrap;
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

  .settings-button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .settings-meta {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
  }

  .settings-success {
    color: #2f8a4d;
    font-size: 0.8rem;
    font-weight: 600;
  }

  .settings-error {
    color: #c0392b;
    font-size: 0.8rem;
    font-weight: 600;
  }

  .settings-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem 1.25rem;
  }

  .settings-grid .settings-actions,
  .settings-grid .settings-error,
  .settings-grid .settings-success,
  .settings-grid .settings-meta {
    grid-column: 1 / -1;
  }

  @media (max-width: 900px) {
    .settings-grid {
      grid-template-columns: 1fr;
    }
  }

  .settings-autocomplete {
    position: relative;
  }

  .settings-suggestions {
    position: absolute;
    z-index: 40;
    top: calc(100% + 6px);
    left: 0;
    right: 0;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.6rem;
    box-shadow: 0 14px 28px rgba(0, 0, 0, 0.14);
    max-height: 360px;
    overflow-y: auto;
    padding: 0.25rem 0;
  }

  .settings-suggestion {
    display: block;
    width: 100%;
    text-align: left;
    padding: 0.5rem 0.75rem;
    background: transparent;
    border: none;
    color: var(--color-card-foreground);
    font-size: 0.85rem;
    cursor: pointer;
  }

  .settings-suggestion:hover {
    background: var(--color-sidebar-accent);
  }

  .settings-suggestion.active {
    background: var(--color-sidebar-accent);
    font-weight: 600;
  }

  .settings-suggestion.muted {
    color: var(--color-muted-foreground);
    cursor: default;
  }

  :global(.spin) {
    animation: spin 1s linear infinite;
  }

  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }

  .settings-dialog {
    max-width: 1200px;
    width: min(96vw, 1200px);
    max-height: min(85vh, 680px);
    overflow: auto;
    display: flex;
    flex-direction: column;
  }

  .settings-header {
    border-bottom: 1px solid var(--color-border);
    padding-bottom: 0.75rem;
  }

  .settings-layout {
    flex: 1;
    overflow: visible;
  }

  .settings-nav {
    overflow-y: auto;
  }

  .settings-content {
    overflow: visible;
    padding-right: 0.5rem;
  }

</style>
