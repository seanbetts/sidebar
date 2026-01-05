import type { Message } from '$lib/types/chat';
import type { Conversation, ConversationWithMessages } from '$lib/types/history';
import type { IngestionListResponse, IngestionMetaResponse } from '$lib/types/ingestion';
import type {
  ThingsBridgeDiagnostics,
  ThingsBridgeStatus,
  ThingsCountsResponse,
  ThingsListResponse
} from '$lib/types/things';

/**
 * API service for conversations.
 */
class ConversationsAPI {
  private get baseUrl(): string {
    return '/api/v1/conversations';
  }

  /**
   * Create a new conversation.
   *
   * @param title - Conversation title (defaults to "New Chat").
   * @returns Newly created conversation.
   * @throws Error when the request fails.
   */
  async create(title: string = 'New Chat'): Promise<Conversation> {
    const response = await fetch(`${this.baseUrl}/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title })
    });
    if (!response.ok) throw new Error('Failed to create conversation');
    return response.json();
  }

  /**
   * List conversations for the current user.
   *
   * @returns Array of conversation summaries.
   * @throws Error when the request fails.
   */
  async list(): Promise<Conversation[]> {
    const response = await fetch(`${this.baseUrl}/`);
    if (!response.ok) throw new Error('Failed to list conversations');
    return response.json();
  }

  /**
   * Fetch a conversation and its messages by ID.
   *
   * @param id - Conversation ID.
   * @returns Conversation with messages.
   * @throws Error when the request fails.
   */
  async get(id: string): Promise<ConversationWithMessages> {
    const response = await fetch(`${this.baseUrl}/${id}`);
    if (!response.ok) throw new Error('Failed to get conversation');
    return response.json();
  }

  /**
   * Append a message to an existing conversation.
   *
   * @param conversationId - Conversation ID.
   * @param message - Message to persist.
   * @throws Error when the request fails.
   */
  async addMessage(conversationId: string, message: Message): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${conversationId}/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id: message.id,
        role: message.role,
        content: message.content,
        status: message.status,
        timestamp: message.timestamp.toISOString(),
        toolCalls: message.toolCalls,
        error: message.error
      })
    });
    if (!response.ok) throw new Error('Failed to add message');
  }

  /**
   * Update conversation metadata.
   *
   * @param id - Conversation ID.
   * @param updates - Partial conversation fields to update.
   * @throws Error when the request fails.
   */
  async update(id: string, updates: Partial<Conversation>): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updates)
    });
    if (!response.ok) throw new Error('Failed to update conversation');
  }

  /**
   * Delete a conversation by ID.
   *
   * @param id - Conversation ID.
   * @throws Error when the request fails.
   */
  async delete(id: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}`, {
      method: 'DELETE'
    });
    if (!response.ok) throw new Error('Failed to delete conversation');
  }

  /**
   * Search conversations by query string.
   *
   * @param query - Search term.
   * @param limit - Max results to return. Defaults to 10.
   * @returns Matching conversations.
   * @throws Error when the request fails.
   */
  async search(query: string, limit: number = 10): Promise<Conversation[]> {
    const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`, {
      method: 'POST'
    });
    if (!response.ok) throw new Error('Failed to search conversations');
    return response.json();
  }
}

export const conversationsAPI = new ConversationsAPI();

/**
 * API service for file ingestion.
 */
class IngestionAPI {
  private get baseUrl(): string {
    return '/api/v1/ingestion';
  }

  /**
   * List ingestion records.
   *
   * @returns Ingestion list response.
   */
  async list(): Promise<IngestionListResponse> {
    const response = await fetch(`${this.baseUrl}`);
    if (!response.ok) throw new Error('Failed to list ingestions');
    return response.json();
  }

  /**
   * Fetch ingestion metadata by file id.
   *
   * @param fileId Ingestion file id.
   * @returns Ingestion metadata.
   */
  async get(fileId: string): Promise<IngestionMetaResponse> {
    const response = await fetch(`${this.baseUrl}/${fileId}/meta`);
    if (!response.ok) throw new Error('Failed to get ingestion metadata');
    return response.json();
  }

  /**
   * Upload a file for ingestion.
   *
   * @param file File to upload.
   * @param onProgress Optional progress callback.
   * @returns Upload response payload.
   */
  async upload(file: File, onProgress?: (progress: number) => void): Promise<{ file_id: string }> {
    const formData = new FormData();
    formData.append('file', file);
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest();
      request.open('POST', this.baseUrl);
      request.withCredentials = true;
      request.upload.addEventListener('progress', event => {
        if (!event.lengthComputable || !onProgress) return;
        const percent = (event.loaded / event.total) * 100;
        onProgress(percent);
      });
      request.onload = () => {
        const isOk = request.status >= 200 && request.status < 300;
        if (!isOk) {
          let message = 'Failed to upload file';
          try {
            const data = JSON.parse(request.responseText);
            if (data?.detail) {
              message = data.detail;
            }
          } catch {
            // Ignore parse errors and use fallback message.
          }
          if (request.status === 413) {
            message = 'File too large. Max size is 100MB.';
          }
          reject(new Error(message));
          return;
        }
        try {
          const payload = JSON.parse(request.responseText);
          resolve(payload);
        } catch {
          reject(new Error('Failed to upload file'));
        }
      };
      request.onerror = () => {
        reject(new Error('Failed to upload file'));
      };
      request.send(formData);
    });
  }

  /**
   * Queue a YouTube URL for ingestion.
   *
   * @param url YouTube URL to ingest.
   * @returns Ingestion response payload.
   */
  async ingestYoutube(url: string): Promise<{ file_id: string }> {
    const response = await fetch(`${this.baseUrl}/youtube`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url })
    });
    if (!response.ok) {
      let message = 'Failed to add YouTube video';
      try {
        const data = await response.json();
        if (data?.detail) {
          message = data.detail;
        }
      } catch {
        // Ignore parse errors and use fallback message.
      }
      throw new Error(message);
    }
    return response.json();
  }

  /**
   * Fetch a derivative asset for viewing.
   *
   * @param fileId Ingestion file id.
   * @param kind Derivative kind to fetch.
   * @returns Fetch response.
   */
  async getContent(fileId: string, kind: string): Promise<Response> {
    const response = await fetch(
      `${this.baseUrl}/${fileId}/content?kind=${encodeURIComponent(kind)}`
    );
    if (!response.ok) throw new Error('Failed to fetch ingestion content');
    return response;
  }

  async pause(fileId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/pause`, { method: 'POST' });
    if (!response.ok) throw new Error('Failed to pause ingestion');
  }

  async resume(fileId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/resume`, { method: 'POST' });
    if (!response.ok) throw new Error('Failed to resume ingestion');
  }

  async cancel(fileId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/cancel`, { method: 'POST' });
    if (!response.ok) throw new Error('Failed to cancel ingestion');
  }

  async delete(fileId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}`, { method: 'DELETE' });
    if (response.status === 404) return;
    if (!response.ok) throw new Error('Failed to delete ingestion');
  }

  async setPinned(fileId: string, pinned: boolean): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned })
    });
    if (!response.ok) throw new Error('Failed to update pinned state');
  }

  async rename(fileId: string, filename: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ filename })
    });
    if (!response.ok) throw new Error('Failed to rename file');
  }

  async updatePinnedOrder(order: string[]): Promise<void> {
    const response = await fetch(`${this.baseUrl}/pinned-order`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order })
    });
    if (!response.ok) throw new Error('Failed to update pinned order');
  }
}

export const ingestionAPI = new IngestionAPI();

/**
 * API service for notes.
 */
class NotesAPI {
  private get baseUrl(): string {
    return '/api/v1/notes';
  }

  /**
   * Fetch the notes tree structure.
   *
   * @returns Tree payload with children nodes.
   * @throws Error when the request fails.
   */
  async listTree(): Promise<{ children: unknown[] }> {
    const response = await fetch(`${this.baseUrl}/tree`);
    if (!response.ok) throw new Error('Failed to list notes tree');
    return response.json();
  }

  /**
   * Search notes by query string.
   *
   * @param query - Search term.
   * @param limit - Max results to return. Defaults to 50.
   * @returns Array of matching note items.
   * @throws Error when the request fails.
   */
  async search(query: string, limit: number = 50): Promise<unknown[]> {
    const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`, {
      method: 'POST'
    });
    if (!response.ok) throw new Error('Failed to search notes');
    const data = await response.json();
    return data.items || [];
  }

  async updatePinnedOrder(order: string[]): Promise<void> {
    const response = await fetch(`${this.baseUrl}/pinned-order`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order })
    });
    if (!response.ok) throw new Error('Failed to update pinned order');
  }
}

/**
 * API service for websites.
 */
class WebsitesAPI {
  private get baseUrl(): string {
    return '/api/v1/websites';
  }

  /**
   * List saved websites.
   *
   * @returns List payload with website items.
   * @throws Error when the request fails.
   */
  async list(): Promise<{ items: unknown[] }> {
    const response = await fetch(`${this.baseUrl}`);
    if (!response.ok) throw new Error('Failed to list websites');
    return response.json();
  }

  /**
   * Fetch a website by ID.
   *
   * @param id - Website ID.
   * @returns Website payload.
   * @throws Error when the request fails.
   */
  async get(id: string): Promise<unknown> {
    const response = await fetch(`${this.baseUrl}/${id}`);
    if (!response.ok) throw new Error('Failed to get website');
    return response.json();
  }

  /**
   * Search websites by query string.
   *
   * @param query - Search term.
   * @param limit - Max results to return. Defaults to 50.
   * @returns List payload with website items.
   * @throws Error when the request fails.
   */
  async search(query: string, limit: number = 50): Promise<{ items: unknown[] }> {
    const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`, {
      method: 'POST'
    });
    if (!response.ok) throw new Error('Failed to search websites');
    return response.json();
  }

  /**
   * Rename a website title by ID.
   *
   * @param id - Website ID.
   * @param title - New website title.
   * @throws Error when the request fails.
   */
  async rename(id: string, title: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}/rename`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title })
    });
    if (!response.ok) throw new Error('Failed to rename website');
  }

  /**
   * Update pinned state for a website.
   *
   * @param id - Website ID.
   * @param pinned - New pinned state.
   * @throws Error when the request fails.
   */
  async setPinned(id: string, pinned: boolean): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}/pin`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned })
    });
    if (!response.ok) throw new Error('Failed to update website pin');
  }

  /**
   * Update archived state for a website.
   *
   * @param id - Website ID.
   * @param archived - New archived state.
   * @throws Error when the request fails.
   */
  async setArchived(id: string, archived: boolean): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}/archive`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ archived })
    });
    if (!response.ok) throw new Error('Failed to update website archive status');
  }

  /**
   * Delete a website by ID.
   *
   * @param id - Website ID.
   * @throws Error when the request fails.
   */
  async delete(id: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}`, {
      method: 'DELETE'
    });
    if (!response.ok) throw new Error('Failed to delete website');
  }

  async updatePinnedOrder(order: string[]): Promise<void> {
    const response = await fetch(`${this.baseUrl}/pinned-order`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order })
    });
    if (!response.ok) throw new Error('Failed to update pinned order');
  }
}

export const notesAPI = new NotesAPI();
export const websitesAPI = new WebsitesAPI();

/**
 * API service for Things bridge status.
 */
class ThingsAPI {
  private get baseUrl(): string {
    return '/api/v1/things';
  }

  async status(): Promise<ThingsBridgeStatus> {
    const response = await fetch(`${this.baseUrl}/bridges/status`);
    if (!response.ok) throw new Error('Failed to load Things bridge status');
    return response.json();
  }

  async list(scope: string): Promise<ThingsListResponse> {
    const response = await fetch(`${this.baseUrl}/lists/${scope}`);
    if (!response.ok) throw new Error('Failed to load Things list');
    return response.json();
  }

  async projectTasks(projectId: string): Promise<ThingsListResponse> {
    const response = await fetch(`${this.baseUrl}/projects/${projectId}/tasks`);
    if (!response.ok) throw new Error('Failed to load Things project tasks');
    return response.json();
  }

  async areaTasks(areaId: string): Promise<ThingsListResponse> {
    const response = await fetch(`${this.baseUrl}/areas/${areaId}/tasks`);
    if (!response.ok) throw new Error('Failed to load Things area tasks');
    return response.json();
  }

  async search(query: string): Promise<ThingsListResponse> {
    const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}`);
    if (!response.ok) throw new Error('Failed to search Things tasks');
    return response.json();
  }

  async counts(): Promise<ThingsCountsResponse> {
    const response = await fetch(`${this.baseUrl}/counts`);
    if (response.status === 404) {
      return {
        counts: { inbox: 0, today: 0, upcoming: 0 },
        projects: [],
        areas: []
      };
    }
    if (!response.ok) throw new Error('Failed to load Things counts');
    return response.json();
  }

  async diagnostics(): Promise<ThingsBridgeDiagnostics> {
    const response = await fetch(`${this.baseUrl}/diagnostics`);
    if (response.status === 404) {
      return { dbAccess: false, dbPath: null, dbError: 'Diagnostics unavailable' };
    }
    if (!response.ok) throw new Error('Failed to load Things diagnostics');
    return response.json();
  }

  async apply(payload: Record<string, unknown>): Promise<void> {
    const response = await fetch(`${this.baseUrl}/apply`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    if (!response.ok) throw new Error('Failed to apply Things operation');
  }

  async setUrlToken(token: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/bridges/url-token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token })
    });
    if (!response.ok) throw new Error('Failed to save Things URL token');
  }
}

export const thingsAPI = new ThingsAPI();
