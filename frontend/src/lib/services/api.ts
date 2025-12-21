import type { Message } from '$lib/types/chat';
import type { Conversation, ConversationWithMessages } from '$lib/types/history';

/**
 * API service for conversations
 */
class ConversationsAPI {
  private baseUrl = '/api/conversations';

  async create(title: string = 'New Chat'): Promise<Conversation> {
    const response = await fetch(`${this.baseUrl}/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title })
    });
    if (!response.ok) throw new Error('Failed to create conversation');
    return response.json();
  }

  async list(): Promise<Conversation[]> {
    const response = await fetch(`${this.baseUrl}/`);
    if (!response.ok) throw new Error('Failed to list conversations');
    return response.json();
  }

  async get(id: string): Promise<ConversationWithMessages> {
    const response = await fetch(`${this.baseUrl}/${id}`);
    if (!response.ok) throw new Error('Failed to get conversation');
    return response.json();
  }

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

  async update(id: string, updates: Partial<Conversation>): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(updates)
    });
    if (!response.ok) throw new Error('Failed to update conversation');
  }

  async delete(id: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/${id}`, {
      method: 'DELETE'
    });
    if (!response.ok) throw new Error('Failed to delete conversation');
  }

  async search(query: string, limit: number = 10): Promise<Conversation[]> {
    const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`, {
      method: 'POST'
    });
    if (!response.ok) throw new Error('Failed to search conversations');
    return response.json();
  }
}

export const conversationsAPI = new ConversationsAPI();
