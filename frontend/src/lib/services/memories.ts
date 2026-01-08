import type { Memory, MemoryCreate, MemoryUpdate } from '$lib/types/memory';

/**
 * API client for managing memory records.
 */
export class MemoriesAPI {
	private baseUrl = '/api/v1/memories';

	/**
	 * List all memories for the current user.
	 *
	 * @returns Array of memory records.
	 * @throws Error when the request fails.
	 */
	async list(): Promise<Memory[]> {
		const response = await fetch(this.baseUrl);
		if (!response.ok) {
			throw new Error('Failed to list memories');
		}
		return response.json();
	}

	/**
	 * Fetch a memory by ID.
	 *
	 * @param id - Memory ID.
	 * @returns Memory record.
	 * @throws Error when the request fails.
	 */
	async get(id: string): Promise<Memory> {
		const response = await fetch(`${this.baseUrl}/${id}`);
		if (!response.ok) {
			throw new Error('Failed to get memory');
		}
		return response.json();
	}

	/**
	 * Create a new memory record.
	 *
	 * @param payload - Memory creation payload.
	 * @returns Created memory record.
	 * @throws Error when the request fails.
	 */
	async create(payload: MemoryCreate): Promise<Memory> {
		const response = await fetch(this.baseUrl, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(payload)
		});
		if (!response.ok) {
			throw new Error('Failed to create memory');
		}
		return response.json();
	}

	/**
	 * Update an existing memory record.
	 *
	 * @param id - Memory ID.
	 * @param payload - Memory update payload.
	 * @returns Updated memory record.
	 * @throws Error when the request fails.
	 */
	async update(id: string, payload: MemoryUpdate): Promise<Memory> {
		const response = await fetch(`${this.baseUrl}/${id}`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(payload)
		});
		if (!response.ok) {
			throw new Error('Failed to update memory');
		}
		return response.json();
	}

	/**
	 * Delete a memory record by ID.
	 *
	 * @param id - Memory ID.
	 * @throws Error when the request fails.
	 */
	async delete(id: string): Promise<void> {
		const response = await fetch(`${this.baseUrl}/${id}`, {
			method: 'DELETE'
		});
		if (!response.ok) {
			throw new Error('Failed to delete memory');
		}
	}
}

export const memoriesAPI = new MemoriesAPI();
