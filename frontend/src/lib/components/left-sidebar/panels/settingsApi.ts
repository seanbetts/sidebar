/**
 * Fetch the current user settings payload.
 *
 * @returns Settings payload from the API.
 * @throws Error when the request fails.
 */
export async function fetchSettings() {
  const response = await fetch('/api/settings');
  if (!response.ok) {
    throw new Error('Failed to load settings');
  }
  return response.json();
}

/**
 * Save user settings updates.
 *
 * @param payload - Partial settings updates.
 * @returns Updated settings payload.
 * @throws Error when the request fails.
 */
export async function saveSettings(payload: Record<string, unknown>) {
  const response = await fetch('/api/settings', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error('Failed to save settings');
  }

  return response.json();
}

/**
 * Fetch available skills from the API.
 *
 * @returns Array of skill objects.
 * @throws Error when the request fails.
 */
export async function fetchSkills() {
  const response = await fetch('/api/skills');
  if (!response.ok) {
    throw new Error('Failed to load skills');
  }
  const data = await response.json();
  return Array.isArray(data?.skills) ? data.skills : [];
}

/**
 * Fetch location autocomplete suggestions.
 *
 * @param query - Location query string.
 * @returns Array of prediction objects.
 * @throws Error when the request fails.
 */
export async function fetchLocationSuggestions(query: string) {
  const response = await fetch(`/api/places/autocomplete?input=${encodeURIComponent(query)}`);
  if (!response.ok) {
    throw new Error('Failed to load locations');
  }
  const data = await response.json();
  return Array.isArray(data?.predictions) ? data.predictions : [];
}

/**
 * Upload a profile image to the server.
 *
 * @param file - Image file to upload.
 * @returns Upload response payload.
 * @throws Error when the request fails.
 */
export async function uploadProfileImage(file: File) {
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
  return response.json();
}

/**
 * Delete the current profile image.
 *
 * @throws Error when the request fails.
 */
export async function deleteProfileImage() {
  const response = await fetch('/api/settings/profile-image', {
    method: 'DELETE'
  });
  if (!response.ok) {
    throw new Error('Failed to delete profile image');
  }
}

/**
 * Fetch the Shortcuts PAT token.
 */
export async function fetchShortcutsPat() {
  const response = await fetch('/api/settings/shortcuts/pat');
  if (!response.ok) {
    throw new Error('Failed to load shortcuts token');
  }
  const data = await response.json();
  return data?.token || '';
}

/**
 * Rotate the Shortcuts PAT token.
 */
export async function rotateShortcutsPat() {
  const response = await fetch('/api/settings/shortcuts/pat/rotate', {
    method: 'POST'
  });
  if (!response.ok) {
    throw new Error('Failed to rotate shortcuts token');
  }
  const data = await response.json();
  return data?.token || '';
}
