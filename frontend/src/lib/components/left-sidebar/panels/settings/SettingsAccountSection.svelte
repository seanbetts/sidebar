<script lang="ts">
  import { Loader2, User } from 'lucide-svelte';

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
  export let isLoadingSettings = false;
  export let settingsError = '';
</script>

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

<style>
  .settings-avatar-placeholder {
    width: 100%;
    height: 100%;
    display: grid;
    place-items: center;
    color: var(--color-muted-foreground);
  }

  :global(.dark) .settings-avatar-placeholder {
    color: #9aa3ad;
  }
</style>
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
