import type { Message } from '$lib/types/chat';
import type { Conversation, ConversationWithMessages } from '$lib/types/history';
import type { IngestionListResponse, IngestionMetaResponse } from '$lib/types/ingestion';

/**
 * API service for conversations.
 */
class ConversationsAPI {
  private get baseUrl(): string {
    return '/api/conversations';
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
    return '/api/ingestion';
  }

  /**
   * List ingestion records.
   */
  async list(): Promise<IngestionListResponse> {
    const response = await fetch(`${this.baseUrl}`);
    if (!response.ok) throw new Error('Failed to list ingestions');
    return response.json();
  }

  /**
   * Fetch ingestion metadata by file id.
   */
  async get(fileId: string): Promise<IngestionMetaResponse> {
    const response = await fetch(`${this.baseUrl}/${fileId}/meta`);
    if (!response.ok) throw new Error('Failed to get ingestion metadata');
    return response.json();
  }

  /**
   * Upload a file for ingestion.
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
        } catch (error) {
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
   * Fetch a derivative asset for viewing.
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

  async reprocess(fileId: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${fileId}/reprocess`, { method: 'POST' });
    if (!response.ok) throw new Error('Failed to reprocess ingestion');
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
}

export const ingestionAPI = new IngestionAPI();

/**
 * API service for notes.
 */
class NotesAPI {
  private get baseUrl(): string {
    return '/api/notes';
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
}

/**
 * API service for websites.
 */
class WebsitesAPI {
  private get baseUrl(): string {
    return '/api/websites';
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
}

export const notesAPI = new NotesAPI();
export const websitesAPI = new WebsitesAPI();
