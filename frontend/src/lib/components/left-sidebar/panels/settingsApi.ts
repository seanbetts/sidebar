/**
 * Fetch the current user settings payload.
 *
 * @returns Settings payload from the API.
 * @throws Error when the request fails.
 */
export async function fetchSettings() {
	const response = await fetch('/api/v1/settings');
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
	const response = await fetch('/api/v1/settings', {
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
	const response = await fetch('/api/v1/skills');
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
	const response = await fetch(`/api/v1/places/autocomplete?input=${encodeURIComponent(query)}`);
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
	const response = await fetch('/api/v1/settings/profile-image', {
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
	const response = await fetch('/api/v1/settings/profile-image', {
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
	const response = await fetch('/api/v1/settings/shortcuts/pat');
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
	const response = await fetch('/api/v1/settings/shortcuts/pat/rotate', {
		method: 'POST'
	});
	if (!response.ok) {
		throw new Error('Failed to rotate shortcuts token');
	}
	const data = await response.json();
	return data?.token || '';
}

/**
 * Install a store skill by ID with optional provider keys.
 *
 * @param id - Skill ID to install.
 * @param providerKeys - Optional map of provider keys needed by the skill.
 * @returns Install response payload.
 * @throws Error when the request fails.
 */
export async function installSkill(id: string, providerKeys?: Record<string, string>) {
	const response = await fetch(`/api/v1/skills/${id}/install`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify(providerKeys ? { provider_keys: providerKeys } : {})
	});
	if (!response.ok) {
		throw new Error('Failed to install skill');
	}
	return response.json();
}

/**
 * Uninstall a store skill by ID.
 *
 * @param id - Skill ID to uninstall.
 * @throws Error when the request fails.
 */
export async function uninstallSkill(id: string) {
	const response = await fetch(`/api/v1/skills/${id}`, { method: 'DELETE' });
	if (!response.ok) {
		throw new Error('Failed to uninstall skill');
	}
}

/**
 * Fetch provider credential status.
 *
 * @param provider - Provider identifier.
 * @returns Provider status payload.
 * @throws Error when the request fails.
 */
export async function fetchProviderStatus(provider: string) {
	const response = await fetch(`/api/v1/settings/provider/${provider}`);
	if (!response.ok) {
		throw new Error('Failed to fetch provider status');
	}
	return response.json();
}

/**
 * Save a provider API key.
 *
 * @param provider - Provider identifier.
 * @param key - API key value.
 * @returns Save response payload.
 * @throws Error when the request fails.
 */
export async function saveProviderKey(provider: string, key: string) {
	const response = await fetch(`/api/v1/settings/provider/${provider}`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ key })
	});
	if (!response.ok) {
		throw new Error('Failed to save provider key');
	}
	return response.json();
}

/**
 * Delete a provider API key.
 *
 * @param provider - Provider identifier.
 * @throws Error when the request fails.
 */
export async function deleteProviderKey(provider: string) {
	const response = await fetch(`/api/v1/settings/provider/${provider}`, { method: 'DELETE' });
	if (!response.ok) {
		throw new Error('Failed to delete provider key');
	}
}

/**
 * Disconnect a provider consumer (skill) from a provider.
 *
 * @param provider - Provider identifier.
 * @param skillId - Skill ID to disconnect.
 * @throws Error when the request fails.
 */
export async function disconnectProviderConsumer(provider: string, skillId: string) {
	const response = await fetch(`/api/v1/settings/provider/${provider}/disconnect`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ skill_id: skillId })
	});
	if (!response.ok) {
		throw new Error('Failed to disconnect provider consumer');
	}
}
