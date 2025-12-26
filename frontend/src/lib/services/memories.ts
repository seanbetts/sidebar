import type { Memory, MemoryCreate, MemoryUpdate } from '$lib/types/memory';

export class MemoriesAPI {
  private baseUrl = '/api/memories';

  async list(): Promise<Memory[]> {
    const response = await fetch(this.baseUrl);
    if (!response.ok) {
      throw new Error('Failed to list memories');
    }
    return response.json();
  }

  async get(id: string): Promise<Memory> {
    const response = await fetch(`${this.baseUrl}/${id}`);
    if (!response.ok) {
      throw new Error('Failed to get memory');
    }
    return response.json();
  }

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
