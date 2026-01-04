<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import SettingsDialog from '$lib/components/left-sidebar/panels/SettingsDialog.svelte';
  import {
    deleteProfileImage as deleteProfileImageRequest,
    fetchLocationSuggestions,
    fetchSettings,
    fetchSkills,
    saveSettings as persistSettings,
    uploadProfileImage as uploadProfileImageRequest
  } from '$lib/components/left-sidebar/panels/settingsApi';
  import {
    PRONOUN_OPTIONS,
    SETTINGS_SECTIONS
  } from '$lib/components/left-sidebar/panels/settingsConstants';
  import { groupSkills, normalizeSkillList } from '$lib/components/left-sidebar/panels/settingsUtils';
  import { logError } from '$lib/utils/errorHandling';

  export let open = false;
  export let profileImageSrc = '';

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
  $: profileImageSrc = profileImageUrl ? `${profileImageUrl}?v=${profileImageVersion}` : '';

  export function handleProfileImageError() {
    profileImageUrl = '';
    profileImageError = 'Failed to load profile image.';
  }

  const pronounOptions = PRONOUN_OPTIONS;
  const settingsSections = SETTINGS_SECTIONS;
  let activeSettingsSection = 'account';

  onMount(() => {
    loadSettings(true);
    loadSkills();
  });

  onDestroy(() => {
    if (locationLookupTimer) clearTimeout(locationLookupTimer);
    if (autosaveTimer) clearTimeout(autosaveTimer);
  });

  async function loadSkills() {
    if (isLoadingSkills) return;
    isLoadingSkills = true;
    skillsError = '';

    try {
      skills = await fetchSkills();
    } catch (error) {
      skillsError =
        error instanceof Error && error.message
          ? error.message
          : 'Failed to load skills.';
    } finally {
      isLoadingSkills = false;
    }
  }

  async function loadSettings(force = false) {
    if (isLoadingSettings || (settingsLoaded && !force)) return;
    isLoadingSettings = true;
    settingsError = '';
    profileImageError = '';
    locationSuggestions = [];

    try {
      const data = await fetchSettings();
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

      const data = await persistSettings(payload);

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
      const data = await uploadProfileImageRequest(file);
      profileImageUrl = data?.profile_image_url ?? profileImageUrl;
      profileImageVersion = Date.now();
    } catch (error) {
      logError('Failed to upload profile image', error, {
        scope: 'SettingsDialogContainer'
      });
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
      await deleteProfileImageRequest();
      profileImageUrl = '';
      profileImageVersion = Date.now();
    } catch (error) {
      logError('Failed to delete profile image', error, {
        scope: 'SettingsDialogContainer'
      });
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
      locationSuggestions = await fetchLocationSuggestions(query);
      activeLocationIndex = locationSuggestions.length ? 0 : -1;
    } catch (error) {
      logError('Failed to load locations', error, {
        scope: 'SettingsDialogContainer',
        query
      });
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
    if (autosaveTimer) {
      clearTimeout(autosaveTimer);
      autosaveTimer = null;
    }

    try {
      if (settingsDirty) {
        await saveSettings();
      }

      settingsLoaded = false;
      settingsError = '';
      locationSuggestions = [];
      profileImageError = '';
    } catch (error) {
      logError('Failed to save settings on close', error, {
        scope: 'SettingsDialogContainer'
      });
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

  $: if (settingsLoaded && open && settingsDirty) {
    scheduleAutosave();
  }

  $: {
    if (wasSettingsOpen && !open) {
      handleSettingsClose().catch((error) => {
        logError('Settings close failed, reopening', error, {
          scope: 'SettingsDialogContainer'
        });
        setTimeout(() => {
          open = true;
        }, 0);
      });
    }
    wasSettingsOpen = open;
  }

  $: if (open && !settingsLoaded) {
    loadSettings();
  }
</script>

<SettingsDialog
  bind:open
  {isLoadingSettings}
  {settingsSections}
  {activeSettingsSection}
  setActiveSection={(section) => (activeSettingsSection = section)}
  {profileImageSrc}
  {profileImageError}
  {isUploadingProfileImage}
  {handleProfileImageChange}
  {deleteProfileImage}
  handleProfileImageError={handleProfileImageError}
  bind:name
  bind:jobTitle
  bind:employer
  bind:dateOfBirth
  bind:gender
  bind:pronouns
  {pronounOptions}
  bind:location
  {isLoadingLocations}
  {locationLookupError}
  {locationSuggestions}
  {activeLocationIndex}
  {handleLocationInput}
  {handleLocationKeydown}
  {handleLocationBlur}
  {selectLocation}
  {settingsError}
  bind:communicationStyle
  bind:workingRelationship
  {isLoadingSkills}
  {skillsError}
  {skills}
  {groupSkills}
  {enabledSkills}
  {allSkillsEnabled}
  {toggleAllSkills}
  {toggleSkill}
/>
