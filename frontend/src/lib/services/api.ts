import type { Message } from '$lib/types/chat';
import type { FileNode } from '$lib/types/file';
import type { Conversation, ConversationWithMessages } from '$lib/types/history';
import type { IngestionListResponse, IngestionMetaResponse } from '$lib/types/ingestion';
import type {
	TaskCountsResponse,
	TaskGroup,
	TaskListResponse,
	TaskProject,
	TaskSyncResponse
} from '$lib/types/tasks';

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
		const response = await fetch(
			`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`,
			{
				method: 'POST'
			}
		);
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
		return '/api/v1/files';
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
			request.upload.addEventListener('progress', (event) => {
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
	async listTree(): Promise<{ children: FileNode[] }> {
		const response = await fetch(`${this.baseUrl}/tree`);
		if (!response.ok) throw new Error('Failed to list notes tree');
		const data = await response.json();
		return {
			children: Array.isArray(data?.children) ? (data.children as FileNode[]) : []
		};
	}

	/**
	 * Search notes by query string.
	 *
	 * @param query - Search term.
	 * @param limit - Max results to return. Defaults to 50.
	 * @returns Array of matching note items.
	 * @throws Error when the request fails.
	 */
	async search(query: string, limit: number = 50): Promise<FileNode[]> {
		const response = await fetch(
			`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`,
			{
				method: 'POST'
			}
		);
		if (!response.ok) throw new Error('Failed to search notes');
		const data = await response.json();
		return Array.isArray(data?.items) ? (data.items as FileNode[]) : [];
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
	 * List archived websites.
	 *
	 * @returns List payload with archived website items.
	 * @throws Error when the request fails.
	 */
	async listArchived(limit: number = 200, offset: number = 0): Promise<{ items: unknown[] }> {
		const params = new URLSearchParams({
			limit: String(limit),
			offset: String(offset)
		});
		const response = await fetch(`${this.baseUrl}/archived?${params.toString()}`);
		if (!response.ok) throw new Error('Failed to list archived websites');
		return response.json();
	}

	/**
	 * Save a website URL.
	 *
	 * @param url - Website URL to save.
	 * @returns Save response payload.
	 * @throws Error when the request fails.
	 */
	async save(url: string): Promise<unknown> {
		const response = await fetch(`${this.baseUrl}/save`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ url })
		});
		if (!response.ok) throw new Error('Failed to save website');
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
		const response = await fetch(
			`${this.baseUrl}/search?query=${encodeURIComponent(query)}&limit=${limit}`,
			{
				method: 'POST'
			}
		);
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

	async transcribeYouTube(id: string, url: string): Promise<unknown> {
		const response = await fetch(`${this.baseUrl}/${id}/youtube-transcript`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ url })
		});
		if (response.status === 202) {
			return response.json();
		}
		if (!response.ok) throw new Error('Failed to transcribe YouTube video');
		return response.json();
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
 * API service for tasks.
 */
class TasksAPI {
	private get baseUrl(): string {
		return '/api/v1/tasks';
	}

	private buildOperationId(): string {
		if (globalThis.crypto?.randomUUID) {
			return globalThis.crypto.randomUUID();
		}
		return `op-${Date.now()}-${Math.random().toString(16).slice(2)}`;
	}

	private withOperationId(operation: Record<string, unknown>): Record<string, unknown> {
		if (operation.operation_id) return operation;
		return { ...operation, operation_id: this.buildOperationId() };
	}

	async list(scope: string): Promise<TaskListResponse> {
		const response = await fetch(`${this.baseUrl}/lists/${scope}`);
		if (!response.ok) throw new Error('Failed to load task list');
		return response.json();
	}

	async projectTasks(projectId: string): Promise<TaskListResponse> {
		const response = await fetch(`${this.baseUrl}/projects/${projectId}/tasks`);
		if (!response.ok) throw new Error('Failed to load project tasks');
		return response.json();
	}

	async groupTasks(groupId: string): Promise<TaskListResponse> {
		const response = await fetch(`${this.baseUrl}/groups/${groupId}/tasks`);
		if (!response.ok) throw new Error('Failed to load group tasks');
		return response.json();
	}

	async search(query: string): Promise<TaskListResponse> {
		const response = await fetch(`${this.baseUrl}/search?query=${encodeURIComponent(query)}`);
		if (!response.ok) throw new Error('Failed to search tasks');
		return response.json();
	}

	async counts(): Promise<TaskCountsResponse> {
		const response = await fetch(`${this.baseUrl}/counts`);
		if (response.status === 404) {
			return {
				counts: { inbox: 0, today: 0, upcoming: 0 },
				projects: [],
				groups: []
			};
		}
		if (!response.ok) throw new Error('Failed to load task counts');
		return response.json();
	}

	async createGroup(title: string): Promise<TaskGroup> {
		const response = await fetch(`${this.baseUrl}/groups`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ title })
		});
		if (!response.ok) throw new Error('Failed to create task group');
		return response.json();
	}

	async renameGroup(groupId: string, title: string): Promise<TaskGroup> {
		const response = await fetch(`${this.baseUrl}/groups/${groupId}`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ title })
		});
		if (!response.ok) throw new Error('Failed to rename task group');
		return response.json();
	}

	async deleteGroup(groupId: string): Promise<void> {
		const response = await fetch(`${this.baseUrl}/groups/${groupId}`, {
			method: 'DELETE'
		});
		if (!response.ok) throw new Error('Failed to delete task group');
	}

	async createProject(title: string, groupId: string | null): Promise<TaskProject> {
		const response = await fetch(`${this.baseUrl}/projects`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ title, groupId })
		});
		if (!response.ok) throw new Error('Failed to create task project');
		return response.json();
	}

	async renameProject(projectId: string, title: string): Promise<TaskProject> {
		const response = await fetch(`${this.baseUrl}/projects/${projectId}`, {
			method: 'PATCH',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({ title })
		});
		if (!response.ok) throw new Error('Failed to rename task project');
		return response.json();
	}

	async deleteProject(projectId: string): Promise<void> {
		const response = await fetch(`${this.baseUrl}/projects/${projectId}`, {
			method: 'DELETE'
		});
		if (!response.ok) throw new Error('Failed to delete task project');
	}

	async apply(payload: Record<string, unknown>): Promise<void> {
		const normalizedPayload =
			Array.isArray(payload.operations) && payload.operations.length
				? { ...payload, operations: payload.operations.map((op) => this.withOperationId(op)) }
				: this.withOperationId(payload);
		const response = await fetch(`${this.baseUrl}/apply`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(normalizedPayload)
		});
		if (!response.ok) throw new Error('Failed to apply task operation');
	}

	async sync(payload: {
		last_sync: string | null;
		operations: Record<string, unknown>[];
	}): Promise<TaskSyncResponse> {
		const normalized = {
			...payload,
			operations: payload.operations.map((operation) => this.withOperationId(operation))
		};
		const response = await fetch(`${this.baseUrl}/sync`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(normalized)
		});
		if (!response.ok) throw new Error('Failed to sync tasks');
		return response.json();
	}
}

export const tasksAPI = new TasksAPI();
