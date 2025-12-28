export async function fetchSettings() {
  const response = await fetch('/api/settings');
  if (!response.ok) {
    throw new Error('Failed to load settings');
  }
  return response.json();
}

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

export async function fetchSkills() {
  const response = await fetch('/api/skills');
  if (!response.ok) {
    throw new Error('Failed to load skills');
  }
  const data = await response.json();
  return Array.isArray(data?.skills) ? data.skills : [];
}

export async function fetchLocationSuggestions(query: string) {
  const response = await fetch(`/api/places/autocomplete?input=${encodeURIComponent(query)}`);
  if (!response.ok) {
    throw new Error('Failed to load locations');
  }
  const data = await response.json();
  return Array.isArray(data?.predictions) ? data.predictions : [];
}

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

export async function deleteProfileImage() {
  const response = await fetch('/api/settings/profile-image', {
    method: 'DELETE'
  });
  if (!response.ok) {
    throw new Error('Failed to delete profile image');
  }
}
