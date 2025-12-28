<script lang="ts">
  import { Loader2, LogOut, User } from 'lucide-svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import { Button } from '$lib/components/ui/button';
  import MemorySettings from '$lib/components/settings/MemorySettings.svelte';
  import SettingsAccountSection from '$lib/components/left-sidebar/panels/settings/SettingsAccountSection.svelte';
  import SettingsSystemSection from '$lib/components/left-sidebar/panels/settings/SettingsSystemSection.svelte';
  import SettingsSkillsSection from '$lib/components/left-sidebar/panels/settings/SettingsSkillsSection.svelte';

  export let open = false;
  export let isLoadingSettings = false;
  export let settingsSections: Array<{ key: string; label: string; icon: typeof User }> = [];
  export let activeSettingsSection = 'account';
  export let setActiveSection: (key: string) => void;
  export let profileImageSrc = '';
  export let profileImageError = '';
  export let isUploadingProfileImage = false;
  export let handleProfileImageChange: (event: Event) => void;
  export let deleteProfileImage: () => void;
  export let handleProfileImageError: () => void;
  export let name = '';
  export let jobTitle = '';
  export let employer = '';
  export let dateOfBirth = '';
  export let gender = '';
  export let pronouns = '';
  export let pronounOptions: string[] = [];
  export let location = '';
  export let isLoadingLocations = false;
  export let locationLookupError = '';
  export let locationSuggestions: Array<{ description: string; place_id: string }> = [];
  export let activeLocationIndex = -1;
  export let handleLocationInput: () => void;
  export let handleLocationKeydown: (event: KeyboardEvent) => void;
  export let handleLocationBlur: () => void;
  export let selectLocation: (value: string) => void;
  export let settingsError = '';
  export let communicationStyle = '';
  export let workingRelationship = '';
  export let isLoadingSkills = false;
  export let skillsError = '';
  export let skills: Array<{ id: string; name: string; description: string; category?: string }> = [];
  export let groupSkills: (
    list: Array<{ id: string; name: string; description: string; category?: string }>
  ) => Array<[string, Array<{ id: string; name: string; description: string; category?: string }>]>;
  export let enabledSkills: string[] = [];
  export let allSkillsEnabled = false;
  export let toggleAllSkills: (enabled: boolean) => void;
  export let toggleSkill: (id: string, enabled: boolean) => void;
</script>

<AlertDialog.Root bind:open>
  <AlertDialog.Content class="settings-dialog-container">
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
            on:click={() => setActiveSection(section.key)}
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
          <SettingsAccountSection
            bind:name
            bind:jobTitle
            bind:employer
            bind:dateOfBirth
            bind:gender
            bind:pronouns
            bind:location
            bind:activeLocationIndex
            {pronounOptions}
            {profileImageSrc}
            {profileImageError}
            {isUploadingProfileImage}
            {handleProfileImageChange}
            {deleteProfileImage}
            {handleProfileImageError}
            {isLoadingLocations}
            {locationLookupError}
            {locationSuggestions}
            {handleLocationInput}
            {handleLocationKeydown}
            {handleLocationBlur}
            {selectLocation}
            {isLoadingSettings}
            {settingsError}
          />
        {:else if activeSettingsSection === 'system'}
          <SettingsSystemSection
            bind:communicationStyle
            bind:workingRelationship
            {isLoadingSettings}
            {settingsError}
          />
        {:else if activeSettingsSection === 'memory'}
          <MemorySettings />
        {:else}
          <SettingsSkillsSection
            {skills}
            {skillsError}
            {isLoadingSkills}
            {groupSkills}
            {enabledSkills}
            {allSkillsEnabled}
            {toggleAllSkills}
            {toggleSkill}
          />
        {/if}
      </div>
    </div>
    <AlertDialog.Footer class="settings-footer">
      <form method="get" action="/auth/logout">
        <Button
          type="submit"
          variant="outline"
          class="settings-logout"
          aria-label="Sign out"
        >
          <LogOut size={16} />
          <span>Sign out</span>
        </Button>
      </form>
      <AlertDialog.Action onclick={() => (open = false)}>Close</AlertDialog.Action>
    </AlertDialog.Footer>
  </AlertDialog.Content>
</AlertDialog.Root>

<style>
  .settings-layout {
    display: grid;
    grid-template-columns: 240px 1fr;
    gap: 1.5rem;
    padding: 1.25rem 0 0;
  }

  .settings-nav {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    border-right: 1px solid var(--color-border);
    padding-right: 1rem;
    height: 100%;
  }

  .settings-logout {
    justify-content: flex-start;
    gap: 0.5rem;
  }

  :global([data-slot='alert-dialog-footer'].settings-footer) {
    width: 100%;
    display: flex;
    flex-direction: row !important;
    align-items: center;
    justify-content: space-between !important;
    gap: 0.75rem;
  }

  :global([data-slot='alert-dialog-footer'].settings-footer form) {
    margin: 0;
  }

  .settings-nav-item {
    display: flex;
    align-items: center;
    gap: 0.65rem;
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
    padding: 0.5rem 0.75rem;
    border-radius: 0.6rem;
    border: none;
    background: transparent;
    cursor: pointer;
    transition: background 0.2s ease, color 0.2s ease;
  }

  .settings-nav-item:hover {
    color: var(--color-sidebar-foreground);
    background: var(--color-sidebar-accent);
  }

  .settings-nav-item.active {
    color: var(--color-sidebar-foreground);
    background: var(--color-sidebar-accent);
  }

  :global(.settings-content h3) {
    font-size: 1rem;
    margin-bottom: 0.35rem;
  }

  :global(.settings-content p) {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
    margin-bottom: 1rem;
  }

  :global(.settings-form) {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  :global(.settings-label) {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  :global(.settings-textarea) {
    border-radius: 0.75rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    padding: 0.75rem;
    font-size: 0.9rem;
    color: var(--color-sidebar-foreground);
    resize: vertical;
  }

  :global(.settings-input) {
    border-radius: 0.75rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    padding: 0.65rem 0.75rem;
    font-size: 0.9rem;
    color: var(--color-sidebar-foreground);
  }

  :global(.settings-textarea:focus),
  :global(.settings-input:focus) {
    outline: none;
    border-color: var(--color-sidebar-accent);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-sidebar-accent) 30%, transparent);
  }

  :global(.settings-actions) {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-top: 0.5rem;
  }

  :global(.settings-button) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.45rem;
    padding: 0.55rem 0.9rem;
    border-radius: 999px;
    border: none;
    font-size: 0.8rem;
    font-weight: 600;
    background: var(--color-sidebar-accent);
    color: var(--color-sidebar-foreground);
    cursor: pointer;
  }

  :global(.settings-button.secondary) {
    background: var(--color-secondary);
    border: 1px solid var(--color-border);
  }

  :global(.settings-button:disabled) {
    opacity: 0.6;
    cursor: not-allowed;
  }

  :global(.settings-meta) {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  :global(.settings-success) {
    color: #2f8a4d;
    font-size: 0.8rem;
  }

  :global(.settings-error) {
    color: #d55b5b;
    font-size: 0.8rem;
  }

  :global(.settings-grid) {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.75rem;
  }

  :global(.settings-grid .settings-actions),
  :global(.settings-grid .settings-error),
  :global(.settings-grid .settings-success),
  :global(.settings-grid .settings-meta) {
    grid-column: 1 / -1;
  }

  @media (max-width: 900px) {
    :global(.settings-grid) {
      grid-template-columns: 1fr;
    }
  }

  :global(.settings-avatar) {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
  }

  :global(.settings-avatar-preview) {
    width: 64px;
    height: 64px;
    border-radius: 16px;
    overflow: hidden;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    display: grid;
    place-items: center;
  }

  :global(.settings-avatar-preview img) {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  :global(.settings-avatar-placeholder) {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    color: var(--color-muted-foreground);
  }

  :global(.settings-avatar-upload) {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.8rem;
    background: var(--color-secondary);
    border: 1px solid var(--color-border);
    padding: 0.5rem 0.75rem;
    border-radius: 999px;
    cursor: pointer;
    color: var(--color-sidebar-foreground);
  }

  :global(.settings-avatar-upload input) {
    display: none;
  }

  :global(.settings-avatar-remove) {
    background: none;
    border: none;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
    cursor: pointer;
  }

  :global(.settings-avatar-remove:disabled) {
    opacity: 0.6;
    cursor: not-allowed;
  }

  :global(.dark) .settings-avatar-placeholder {
    color: #9aa3ad;
  }

  :global(.settings-autocomplete) {
    position: relative;
  }

  :global(.settings-suggestions) {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    right: 0;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    border-radius: 0.6rem;
    padding: 0.35rem;
    z-index: 10;
    max-height: 180px;
    overflow-y: auto;
  }

  :global(.settings-suggestion) {
    display: block;
    width: 100%;
    text-align: left;
    padding: 0.4rem 0.5rem;
    border-radius: 0.5rem;
    border: none;
    background: none;
    font-size: 0.8rem;
    color: var(--color-sidebar-foreground);
    cursor: pointer;
  }

  :global(.settings-suggestion:hover) {
    background: var(--color-sidebar-accent);
  }

  :global(.settings-suggestion.active) {
    background: var(--color-sidebar-accent);
  }

  :global(.settings-suggestion.muted) {
    color: var(--color-muted-foreground);
    cursor: default;
  }

  /* Target the actual rendered dialog element */
  :global([data-slot='alert-dialog-content'].settings-dialog-container) {
    max-width: 1200px !important;
    width: min(96vw, 1200px) !important;
    height: min(85vh, 680px) !important;
    max-height: min(85vh, 680px) !important;
    min-height: min(85vh, 680px) !important;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    transform-origin: bottom left;
  }

  :global([data-slot='alert-dialog-content'].settings-dialog-container[data-state='open']) {
    animation: settings-dialog-in 0.2s ease-out !important;
  }

  :global([data-slot='alert-dialog-content'].settings-dialog-container[data-state='closed']) {
    animation: settings-dialog-out 0.15s ease-in !important;
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
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border-radius: 999px;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    color: var(--color-muted-foreground);
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

  @keyframes settings-dialog-in {
    from {
      opacity: 0;
      transform: scale(0.97);
    }
    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes settings-dialog-out {
    from {
      opacity: 1;
      transform: scale(1);
    }
    to {
      opacity: 0;
      transform: scale(0.97);
    }
  }
</style>
