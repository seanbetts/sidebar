<script lang="ts">
  import { Loader2, User } from 'lucide-svelte';
  import * as AlertDialog from '$lib/components/ui/alert-dialog/index.js';
  import MemorySettings from '$lib/components/settings/MemorySettings.svelte';

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
          <h3>Account</h3>
          <p>Basic details used to personalise prompts.</p>
          <div class="settings-avatar">
            <div class="settings-avatar-preview">
              {#if profileImageSrc}
                <img src={profileImageSrc} alt="Profile" on:error={handleProfileImageError} />
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

  .settings-content h3 {
    font-size: 1rem;
    margin-bottom: 0.35rem;
  }

  .settings-content p {
    font-size: 0.85rem;
    color: var(--color-muted-foreground);
    margin-bottom: 1rem;
  }

  .settings-form {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .settings-label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .settings-textarea {
    border-radius: 0.75rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    padding: 0.75rem;
    font-size: 0.9rem;
    color: var(--color-sidebar-foreground);
    resize: vertical;
  }

  .settings-input {
    border-radius: 0.75rem;
    border: 1px solid var(--color-border);
    background: var(--color-card);
    padding: 0.65rem 0.75rem;
    font-size: 0.9rem;
    color: var(--color-sidebar-foreground);
  }

  .settings-textarea:focus,
  .settings-input:focus {
    outline: none;
    border-color: var(--color-sidebar-accent);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-sidebar-accent) 30%, transparent);
  }

  .settings-actions {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-top: 0.5rem;
  }

  .settings-button {
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

  .settings-button.secondary {
    background: var(--color-secondary);
    border: 1px solid var(--color-border);
  }

  .settings-button:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .settings-meta {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.8rem;
    color: var(--color-muted-foreground);
  }

  .settings-success {
    color: #2f8a4d;
    font-size: 0.8rem;
  }

  .settings-error {
    color: #d55b5b;
    font-size: 0.8rem;
  }

  .settings-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.75rem;
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
    flex-wrap: wrap;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
  }

  .settings-avatar-preview {
    width: 64px;
    height: 64px;
    border-radius: 16px;
    overflow: hidden;
    background: var(--color-card);
    border: 1px solid var(--color-border);
    display: grid;
    place-items: center;
  }

  .settings-avatar-preview img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .settings-avatar-placeholder {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    color: var(--color-muted-foreground);
  }

  .settings-avatar-upload {
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

  .settings-avatar-upload input {
    display: none;
  }

  .settings-avatar-remove {
    background: none;
    border: none;
    color: var(--color-muted-foreground);
    font-size: 0.8rem;
    cursor: pointer;
  }

  .settings-avatar-remove:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  :global(.dark) .settings-avatar-placeholder {
    color: #9aa3ad;
  }

  .settings-autocomplete {
    position: relative;
  }

  .settings-suggestions {
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

  .settings-suggestion {
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

  .settings-suggestion:hover {
    background: var(--color-sidebar-accent);
  }

  .settings-suggestion.active {
    background: var(--color-sidebar-accent);
  }

  .settings-suggestion.muted {
    color: var(--color-muted-foreground);
    cursor: default;
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
</style>
