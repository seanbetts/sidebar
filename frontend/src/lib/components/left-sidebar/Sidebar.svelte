<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { MessageSquare, FileText, Globe, Settings, User, Monitor, Wrench, Menu, Plus, Folder, FolderOpen, Loader2, Brain } from 'lucide-svelte';
  import { conversationListStore } from '$lib/stores/conversations';
  import { chatStore } from '$lib/stores/chat';
  import { editorStore, currentNoteId } from '$lib/stores/editor';
  import { filesStore } from '$lib/stores/files';
  import { websitesStore } from '$lib/stores/websites';
  import SearchBar from './SearchBar.svelte';
  import ConversationList from './ConversationList.svelte';
  import NotesPanel from '$lib/components/left-sidebar/NotesPanel.svelte';
  import FilesPanel from '$lib/components/left-sidebar/FilesPanel.svelte';
  import WebsitesPanel from '$lib/components/websites/WebsitesPanel.svelte';
  import MemorySettings from '$lib/components/settings/MemorySettings.svelte';
  import TextInputDialog from '$lib/components/left-sidebar/dialogs/TextInputDialog.svelte';
  import ConfirmDialog from '$lib/components/left-sidebar/dialogs/ConfirmDialog.svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';

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
  let skills: Array<{ id: string; name: string; description: string; category?: string }> = [];
  let enabledSkills: string[] = [];
  let initialEnabledSkills: string[] = [];
  let isLoadingSkills = false;
  let skillsError = '';
  $: allSkillsEnabled = skills.length > 0 && enabledSkills.length === skills.length;
  let locationSuggestions: Array<{ description: string; place_id: string }> = [];
  let isLoadingLocations = false;
  let locationLookupError = '';
  let locationLookupTimer: ReturnType<typeof setTimeout> | null = null;
  let activeLocationIndex = -1;
  let lastSelectedLocation = '';
  let autosaveTimer: ReturnType<typeof setTimeout> | null = null;
  let wasSettingsOpen = false;
  let settingsDirty = false;
  let profileImageUrl = '';
  let profileImageVersion = 0;
  let isUploadingProfileImage = false;
  let profileImageError = '';
  const sidebarLogoSrc = '/images/logo.svg';
  $: profileImageSrc = profileImageUrl ? `${profileImageUrl}?v=${profileImageVersion}` : '';
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
    { key: 'memory', label: 'Memory', icon: Brain },
    { key: 'skills', label: 'Skills', icon: Wrench }
  ];
  let activeSettingsSection = 'account';
  let loadedSections = new Set<string>();
  let isMounted = false;

  onMount(() => {
    // Mark as mounted to enable reactive data loading
    isMounted = true;

    // Load settings and skills (non-blocking)
    loadSettings(true);
    loadSkills();
    if (typeof window !== 'undefined') {
      window.addEventListener('keydown', handleSectionShortcut);
    }
  });

  onDestroy(() => {
    // Clean up all timers
    if (locationLookupTimer) clearTimeout(locationLookupTimer);
    if (autosaveTimer) clearTimeout(autosaveTimer);

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

  async function loadSkills() {
    if (isLoadingSkills) return;
    isLoadingSkills = true;
    skillsError = '';

    try {
      const response = await fetch('/api/skills');
      if (!response.ok) {
        throw new Error('Failed to load skills');
      }
      const data = await response.json();
      skills = Array.isArray(data?.skills) ? data.skills : [];
    } catch (error) {
      skillsError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to load skills.';
    } finally {
      isLoadingSkills = false;
    }
  }

  function groupSkills(list: Array<{ id: string; name: string; description: string; category?: string }>) {
    const groups = new Map<string, typeof list>();
    list.forEach((skill) => {
      const category = skill.category || 'Other';
      if (!groups.has(category)) {
        groups.set(category, []);
      }
      groups.get(category)?.push(skill);
    });
    return Array.from(groups.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }

  async function loadSettings(force = false) {
    if (isLoadingSettings || (settingsLoaded && !force)) return;
    isLoadingSettings = true;
    settingsError = '';
    profileImageError = '';
    locationSuggestions = [];

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
      profileImageUrl = data?.profile_image_url ?? '';
      enabledSkills = Array.isArray(data?.enabled_skills) ? data.enabled_skills : [];
      initialCommunicationStyle = communicationStyle;
      initialWorkingRelationship = workingRelationship;
      initialName = name;
      initialJobTitle = jobTitle;
      initialEmployer = employer;
      initialDateOfBirth = dateOfBirth;
      initialGender = gender;
      initialPronouns = pronouns;
      initialLocation = location;
      initialEnabledSkills = [...enabledSkills];
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
      const payload = {
        communication_style: communicationStyle,
        working_relationship: workingRelationship,
        name,
        job_title: jobTitle,
        employer,
        date_of_birth: dateOfBirth || null,
        gender,
        pronouns,
        location,
        enabled_skills: enabledSkills
      };

      const response = await fetch('/api/settings', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
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
      enabledSkills = Array.isArray(data?.enabled_skills) ? data.enabled_skills : enabledSkills;

      initialCommunicationStyle = communicationStyle;
      initialWorkingRelationship = workingRelationship;
      initialName = name;
      initialJobTitle = jobTitle;
      initialEmployer = employer;
      initialDateOfBirth = dateOfBirth;
      initialGender = gender;
      initialPronouns = pronouns;
      initialLocation = location;
      initialEnabledSkills = [...enabledSkills];
    } catch (error) {
      settingsError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to save settings.';
    } finally {
      isSavingSettings = false;
    }
  }

  async function uploadProfileImage(file: File) {
    if (isUploadingProfileImage) return;
    isUploadingProfileImage = true;
    profileImageError = '';

    try {
      const response = await fetch('/api/settings/profile-image', {
        method: 'POST',
        headers: {
          'Content-Type': file.type || 'application/octet-stream',
          'X-Filename': file.name
        },
        body: file
      });
      if (!response.ok) {
        throw new Error('Failed to upload profile image');
      }
      const data = await response.json();
      profileImageUrl = data?.profile_image_url ?? profileImageUrl;
      profileImageVersion = Date.now();
    } catch (error) {
      console.error('Failed to upload profile image:', error);
      profileImageError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to upload profile image.';
    } finally {
      isUploadingProfileImage = false;
    }
  }

  async function deleteProfileImage() {
    if (isUploadingProfileImage) return;
    isUploadingProfileImage = true;
    profileImageError = '';

    try {
      const response = await fetch('/api/settings/profile-image', {
        method: 'DELETE'
      });
      if (!response.ok) {
        throw new Error('Failed to delete profile image');
      }
      profileImageUrl = '';
      profileImageVersion = Date.now();
    } catch (error) {
      console.error('Failed to delete profile image:', error);
      profileImageError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to delete profile image.';
    } finally {
      isUploadingProfileImage = false;
    }
  }

  function handleProfileImageChange(event: Event) {
    const target = event.currentTarget as HTMLInputElement | null;
    const file = target?.files?.[0];
    if (!file) return;
    uploadProfileImage(file);
    if (target) target.value = '';
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
    enabledSkills = [...initialEnabledSkills];
    settingsError = '';
  }

  function toggleSkill(name: string, enabled: boolean) {
    if (enabled) {
      enabledSkills = [...new Set([...enabledSkills, name])];
    } else {
      enabledSkills = enabledSkills.filter((skill) => skill !== name);
    }
  }

  function toggleAllSkills(enabled: boolean) {
    if (enabled) {
      enabledSkills = skills.map((skill) => skill.id);
    } else {
      enabledSkills = [];
    }
  }

  async function handleNewChat() {
    await chatStore.clear();
    await conversationListStore.refresh();
  }

  function toggleSidebar() {
    isCollapsed = !isCollapsed;
  }

  let activeSection: 'history' | 'notes' | 'websites' | 'workspace' = 'notes';

  function openSection(section: typeof activeSection) {
    activeSection = section;
    isCollapsed = false;
  }

  // Lazy load section data when switching sections (only after mount to ensure stores are ready)
  $: if (isMounted && activeSection) {
    loadSectionData(activeSection);
  }

  function loadSectionData(section: typeof activeSection) {
    // Only load each section once (track by Set to prevent duplicates)
    if (loadedSections.has(section)) {
      return;
    }

    // Check if data already exists to prevent unnecessary reloads
    const hasData = {
      'notes': $filesStore.trees?.['notes']?.loaded ?? false,
      'websites': $websitesStore.loaded ?? false,
      'workspace': $filesStore.trees?.['.']?.loaded ?? false,
      'history': $conversationListStore.loaded ?? false
    }[section];

    // If data already exists, mark as loaded and skip
    if (hasData) {
      loadedSections.add(section);
      return;
    }

    // Mark as loading before calling load to prevent race conditions
    loadedSections.add(section);

    // Load data based on section
    switch (section) {
      case 'notes':
        filesStore.load('notes');
        break;
      case 'websites':
        websitesStore.load();
        break;
      case 'workspace':
        filesStore.load('.');
        break;
      case 'history':
        conversationListStore.load();
        break;
    }
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
    if (autosaveTimer) {
      clearTimeout(autosaveTimer);
    }
    autosaveTimer = setTimeout(() => {
      saveSettings();
    }, 800);
  }

  async function handleSettingsClose() {
    // Clear autosave timer to prevent duplicate saves
    if (autosaveTimer) {
      clearTimeout(autosaveTimer);
      autosaveTimer = null;
    }

    try {
      if (settingsDirty) {
        await saveSettings();
      }

      // Only reset state if save succeeded (or nothing to save)
      settingsLoaded = false;
      settingsError = '';
      locationSuggestions = [];
      profileImageError = '';
    } catch (error) {
      // Keep settingsLoaded = true so error is visible
      // Don't clear settingsError - it was set by saveSettings()
      console.error('Failed to save settings on close:', error);
      // Re-throw to prevent settings from closing with unsaved changes
      throw error;
    }
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
      location !== initialLocation ||
      normalizeSkillList(enabledSkills) !== normalizeSkillList(initialEnabledSkills));

  function normalizeSkillList(list: string[]) {
    return [...new Set(list)].sort().join('|');
  }

  $: if (settingsLoaded && isSettingsOpen && settingsDirty) {
    scheduleAutosave();
  }

  // Track settings close and handle save - combined to avoid reactive cycle
  $: {
    if (wasSettingsOpen && !isSettingsOpen) {
      handleSettingsClose().catch((error) => {
        // If save fails, re-open settings so user can see error and retry
        console.error('Settings close failed, reopening:', error);
        setTimeout(() => {
          isSettingsOpen = true;
        }, 0);
      });
    }
    wasSettingsOpen = isSettingsOpen;
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

      // Reload the files tree and open the new note
      await filesStore.load('notes', true);
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

<TextInputDialog
  bind:open={isNewNoteDialogOpen}
  title="Create a new note"
  description="Pick a name. We'll save it as a markdown file."
  placeholder="Note name"
  bind:value={newNoteName}
  isBusy={isCreatingNote}
  busyLabel="Creating..."
  confirmLabel="Create note"
  onConfirm={createNoteFromDialog}
  onCancel={() => (isNewNoteDialogOpen = false)}
/>

<TextInputDialog
  bind:open={isNewFolderDialogOpen}
  title="Create a new folder"
  description="Folders help organize your notes."
  placeholder="Folder name"
  bind:value={newFolderName}
  isBusy={isCreatingFolder}
  busyLabel="Creating..."
  confirmLabel="Create folder"
  onConfirm={createFolderFromDialog}
  onCancel={() => (isNewFolderDialogOpen = false)}
/>

<TextInputDialog
  bind:open={isNewWorkspaceFolderDialogOpen}
  title="Create a new folder"
  description="Folders help organize your files."
  placeholder="Folder name"
  bind:value={newWorkspaceFolderName}
  isBusy={isCreatingWorkspaceFolder}
  busyLabel="Creating..."
  confirmLabel="Create folder"
  onConfirm={createWorkspaceFolderFromDialog}
  onCancel={() => (isNewWorkspaceFolderDialogOpen = false)}
/>

<TextInputDialog
  bind:open={isNewWebsiteDialogOpen}
  title="Save a website"
  description="Paste a URL to save it to your archive."
  placeholder="https://example.com"
  bind:value={newWebsiteUrl}
  isBusy={isSavingWebsite}
  busyLabel="Saving..."
  confirmLabel="Save website"
  onConfirm={saveWebsiteFromDialog}
  onCancel={() => (isNewWebsiteDialogOpen = false)}
/>

<ConfirmDialog
  bind:open={isErrorDialogOpen}
  title="Unable to create note"
  description={errorMessage}
  confirmLabel="OK"
  showCancel={false}
  onConfirm={() => (isErrorDialogOpen = false)}
/>

<ConfirmDialog
  bind:open={isSaveChangesDialogOpen}
  title="Save changes?"
  description="You have unsaved changes. Would you like to save them before switching notes?"
  confirmLabel="Save changes"
  cancelLabel="Don't save"
  onConfirm={confirmSaveAndSwitch}
  onCancel={discardAndSwitch}
/>

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
        {#if isLoadingSettings}
          <div class="settings-loading-mask" aria-live="polite">
            <div class="settings-loading-card">
              <Loader2 size={18} class="spin" />
              <span>Loading settings...</span>
            </div>
          </div>
        {/if}
        {#if activeSettingsSection === 'account'}
          <h3>Account</h3>
          <p>Basic details used to personalise prompts.</p>
          <div class="settings-avatar">
            <div class="settings-avatar-preview">
              {#if profileImageSrc}
                <img src={profileImageSrc} alt="Profile" on:error={() => {
                  profileImageUrl = '';
                  profileImageError = 'Failed to load profile image.';
                }} />
              {:else}
                <div class="settings-avatar-placeholder" aria-hidden="true">
                  <User size={20} />
                </div>
              {/if}
            </div>
            <label class="settings-avatar-upload">
              <input
                type="file"
                accept="image/*"
                on:change={handleProfileImageChange}
                disabled={isUploadingProfileImage}
              />
              {#if isUploadingProfileImage}
                Uploading...
              {:else}
                Upload photo
              {/if}
            </label>
            {#if profileImageError}
              <div class="settings-error">{profileImageError}</div>
            {/if}
            {#if profileImageSrc}
              <button
                type="button"
                class="settings-avatar-remove"
                on:click={deleteProfileImage}
                disabled={isUploadingProfileImage}
              >
                Remove photo
              </button>
            {/if}
          </div>
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
              <span>Home</span>
              <div class="settings-autocomplete">
                <input
                  class="settings-input"
                  type="text"
                  bind:value={location}
                  placeholder="City, region"
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
        {:else if activeSettingsSection === 'memory'}
          <MemorySettings />
        {:else}
          <h3>Skills</h3>
          <div class="skills-header">
            <p>Manage installed skills and permissions here.</p>
            <label class="skill-toggle">
              <input
                type="checkbox"
                checked={allSkillsEnabled}
                on:change={(event) =>
                  toggleAllSkills((event.currentTarget as HTMLInputElement).checked)
                }
              />
              <span class="skill-switch" aria-hidden="true"></span>
              <span class="skill-toggle-label">Enable all</span>
            </label>
          </div>
          <div class="skills-panel">
            {#if isLoadingSkills}
              <div class="settings-meta">
                <Loader2 size={16} class="spin" />
                Loading skills...
              </div>
            {:else if skillsError}
              <div class="settings-error">{skillsError}</div>
            {:else if skills.length === 0}
              <div class="settings-meta">No skills found.</div>
            {:else}
              {#each groupSkills(skills) as [category, categorySkills]}
                <div class="skills-category">
                  <div class="skills-category-title">{category}</div>
                  <div class="skills-grid">
                    {#each categorySkills as skill}
                      <div class="skill-row">
                        <div class="skill-row-header">
                          <div class="skill-name">{skill.name}</div>
                          <label class="skill-toggle">
                            <input
                              type="checkbox"
                              checked={enabledSkills.includes(skill.id)}
                              on:change={(event) =>
                                toggleSkill(skill.id, (event.currentTarget as HTMLInputElement).checked)
                              }
                            />
                            <span class="skill-switch" aria-hidden="true"></span>
                          </label>
                        </div>
                        <div class="skill-description">{skill.description}</div>
                      </div>
                    {/each}
                  </div>
                </div>
              {/each}
            {/if}
          </div>
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
        on:click={() => openSection('workspace')}
        class="rail-btn"
        aria-label="Files"
        title="Files"
      >
        <FolderOpen size={18} />
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
        class="rail-btn rail-btn-avatar"
        aria-label="Open settings"
        title="Settings"
      >
        {#if profileImageSrc}
          <img class="rail-avatar" src={profileImageSrc} alt="Profile" on:error={() => {
            profileImageUrl = '';
            profileImageError = 'Failed to load profile image.';
          }} />
        {:else}
          <img class="rail-avatar rail-avatar-logo" src={sidebarLogoSrc} alt="App logo" />
        {/if}
      </button>
    </div>
  </div>

  <div class="sidebar-panel" aria-hidden={isCollapsed}>
    <div class="panel-body">
      <!-- Notes Section -->
      <div class="panel-section" class:hidden={activeSection !== 'notes'}>
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
          <SearchBar
            onSearch={(query) => filesStore.searchNotes(query)}
            onClear={() => filesStore.load('notes', true)}
            placeholder="Search notes..."
          />
        </div>
        <div class="notes-content">
          <NotesPanel basePath="notes" emptyMessage="No notes found" hideExtensions={true} onFileClick={handleNoteClick} />
        </div>
      </div>

      <!-- Websites Section -->
      <div class="panel-section" class:hidden={activeSection !== 'websites'}>
        <div class="panel-section-header">
          <div class="panel-section-header-row">
            <div class="panel-section-title">Websites</div>
            <div class="panel-section-actions">
              <button class="panel-action" on:click={handleNewWebsite} aria-label="Save website" title="Save website">
                <Plus size={16} />
              </button>
            </div>
          </div>
          <SearchBar
            onSearch={(query) => websitesStore.search(query)}
            onClear={() => websitesStore.load(true)}
            placeholder="Search websites..."
          />
        </div>
        <div class="files-content">
          <WebsitesPanel />
        </div>
      </div>

      <!-- Workspace Section -->
      <div class="panel-section" class:hidden={activeSection !== 'workspace'}>
        <div class="panel-section-header">
          <div class="panel-section-header-row">
            <div class="panel-section-title">Files</div>
            <div class="panel-section-actions">
              <button class="panel-action" on:click={handleNewWorkspaceFolder} aria-label="New folder" title="New folder">
                <Folder size={16} />
              </button>
            </div>
          </div>
          <SearchBar
            onSearch={(query) => filesStore.searchFiles('.', query)}
            onClear={() => filesStore.load('.', true)}
            placeholder="Search files..."
          />
        </div>
        <div class="files-content">
          <FilesPanel />
        </div>
      </div>

      <!-- History Section -->
      <div class="panel-section" class:hidden={activeSection !== 'history'}>
        <div class="panel-section-header">
          <div class="panel-section-header-row">
            <div class="panel-section-title">Chat</div>
            <div class="panel-section-actions"></div>
          </div>
          <SearchBar
            onSearch={(query) => conversationListStore.search(query)}
            onClear={() => conversationListStore.load(true)}
            placeholder="Search conversations..."
          />
        </div>
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

  .panel-section.hidden {
    display: none;
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

  .settings-avatar {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin: 1rem 0 1.5rem;
  }

  .settings-avatar-preview {
    width: 72px;
    height: 72px;
    border-radius: 50%;
    background: var(--color-sidebar-accent);
    color: var(--color-foreground);
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    overflow: hidden;
  }

  .settings-avatar-preview img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .settings-avatar-placeholder {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: rgba(148, 163, 184, 0.18);
    color: rgba(71, 85, 105, 0.9);
  }

  .settings-avatar-upload {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.45rem 0.85rem;
    border-radius: 0.55rem;
    border: 1px solid var(--color-border);
    background: var(--color-secondary);
    color: var(--color-secondary-foreground);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
  }

  .settings-avatar-upload input {
    display: none;
  }

  .settings-avatar-remove {
    border: 0;
    background: transparent;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
  }

  .settings-avatar-remove:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .rail-btn-avatar {
    padding: 0.35rem;
  }

  .rail-avatar {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    object-fit: cover;
  }

  .rail-avatar-logo {
    padding: 3px;
    object-fit: contain;
  }

  :global(.dark) .settings-avatar-placeholder {
    background: rgba(148, 163, 184, 0.26);
    color: rgba(226, 232, 240, 0.9);
  }

  :global(.dark) .rail-avatar-logo {
    filter: invert(1);
  }

  .settings-autocomplete {
    position: relative;
  }

  .skills-panel {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    margin-top: 1rem;
    max-height: 56vh;
    overflow: auto;
    padding-right: 0.25rem;
  }

  .skills-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .skills-header p {
    margin: 0;
  }

  .skill-toggle-label {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
  }

  .skills-category {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .skills-category-title {
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
  }

  .skills-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.85rem;
  }

  .skill-row {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    padding: 0.9rem 1rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-card);
  }

  .skill-row-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .skill-name {
    font-weight: 600;
    color: var(--color-foreground);
  }

  .skill-description {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
    line-height: 1.4;
  }

  @media (max-width: 1100px) {
    .skills-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 700px) {
    .skills-grid {
      grid-template-columns: 1fr;
    }
  }

  .skill-toggle {
    display: inline-flex;
    align-items: center;
    cursor: pointer;
    position: relative;
    gap: 0.5rem;
  }

  .skill-toggle input {
    position: absolute;
    opacity: 0;
    pointer-events: none;
  }

  .skill-switch {
    width: 42px;
    height: 24px;
    border-radius: 999px;
    background: var(--color-border);
    position: relative;
    transition: background 0.2s ease;
  }

  .skill-switch::after {
    content: '';
    position: absolute;
    top: 3px;
    left: 3px;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--color-background);
    transition: transform 0.2s ease;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.25);
  }

  .skill-toggle input:checked + .skill-switch {
    background: var(--color-foreground);
  }

  .skill-toggle input:checked + .skill-switch::after {
    transform: translateX(18px);
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
    height: min(85vh, 680px);
    max-height: min(85vh, 680px);
    min-height: min(85vh, 680px);
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
    min-height: 0;
    overflow: hidden;
  }

  .settings-nav {
    overflow-y: auto;
  }

  .settings-content {
    position: relative;
    height: 100%;
    overflow: auto;
    padding-right: 0.5rem;
  }

  .settings-loading-mask {
    position: absolute;
    inset: 0;
    background: rgba(10, 10, 10, 0.35);
    backdrop-filter: blur(2px);
    display: grid;
    place-items: center;
    z-index: 5;
  }

  .settings-loading-card {
    display: inline-flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.65rem 1rem;
    border-radius: 999px;
    background: var(--color-card);
    color: var(--color-card-foreground);
    border: 1px solid var(--color-border);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.15);
    font-size: 0.85rem;
  }

</style>
