import { afterEach, describe, expect, it, vi } from 'vitest';
import { conversationsAPI, ingestionAPI, notesAPI, websitesAPI, tasksAPI } from '$lib/services/api';

const okJson = (value: unknown) =>
	Promise.resolve({
		ok: true,
		json: async () => value
	} as Response);

const failJson = (status = 500, message = 'Error') =>
	Promise.resolve({
		ok: false,
		status,
		json: async () => ({ detail: message })
	} as Response);

describe('api services', () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it('conversationsAPI.list returns conversations', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson([{ id: '1' }]));

		const data = await conversationsAPI.list();

		expect(data).toEqual([{ id: '1' }]);
	});

	it('conversationsAPI.create posts a title', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'c1' }));

		const data = await conversationsAPI.create('Hello');

		expect(data.id).toBe('c1');
		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/conversations/',
			expect.objectContaining({ method: 'POST' })
		);
	});

	it('conversationsAPI.get returns conversation data', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'c2', messages: [] }));

		const data = await conversationsAPI.get('c2');

		expect(data.id).toBe('c2');
	});

	it('conversationsAPI.addMessage persists timestamps', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));
		const timestamp = new Date('2025-01-01T00:00:00Z');

		await conversationsAPI.addMessage('c1', {
			id: 'm1',
			role: 'user',
			content: 'Hi',
			status: 'complete',
			timestamp
		});

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/conversations/c1/messages',
			expect.objectContaining({
				method: 'POST',
				body: expect.stringContaining(timestamp.toISOString())
			})
		);
	});

	it('conversationsAPI.update sends PUT', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

		await conversationsAPI.update('c3', { title: 'Updated' });

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/conversations/c3',
			expect.objectContaining({ method: 'PUT' })
		);
	});

	it('conversationsAPI.delete throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(conversationsAPI.delete('c4')).rejects.toThrow('Failed to delete conversation');
	});

	it('notesAPI.search throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(notesAPI.search('query')).rejects.toThrow('Failed to search notes');
	});

	it('websitesAPI.list returns items', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ items: [] }));

		const data = await websitesAPI.list();

		expect(data.items).toEqual([]);
	});

	it('websitesAPI.search returns items', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ items: [{ id: 'w1' }] }));

		const data = await websitesAPI.search('sidebar');

		expect(data.items).toHaveLength(1);
	});

	it('ingestionAPI.list throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(ingestionAPI.list()).rejects.toThrow('Failed to list ingestions');
	});

	it('ingestionAPI.ingestYoutube surfaces API detail', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson(400, 'Bad URL'));

		await expect(ingestionAPI.ingestYoutube('bad')).rejects.toThrow('Bad URL');
	});

	it('ingestionAPI.pause throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(ingestionAPI.pause('file-1')).rejects.toThrow('Failed to pause ingestion');
	});

	it('ingestionAPI.resume throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(ingestionAPI.resume('file-1')).rejects.toThrow('Failed to resume ingestion');
	});

	it('ingestionAPI.cancel throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(ingestionAPI.cancel('file-2')).rejects.toThrow('Failed to cancel ingestion');
	});

	it('ingestionAPI.rename posts filename', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

		await ingestionAPI.rename('file-3', 'new.txt');

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/files/file-3/rename',
			expect.objectContaining({ method: 'PATCH' })
		);
	});

	it('ingestionAPI.setPinned updates state', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

		await ingestionAPI.setPinned('file-2', true);

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/files/file-2/pin',
			expect.objectContaining({ method: 'PATCH' })
		);
	});

	it('ingestionAPI.getContent returns response', async () => {
		const response = { ok: true } as Response;
		const fetchSpy = vi.spyOn(global, 'fetch').mockResolvedValue(response);

		const data = await ingestionAPI.getContent('file-9', 'ai_md');

		expect(data).toBe(response);
		expect(fetchSpy).toHaveBeenCalledWith('/api/v1/files/file-9/content?kind=ai_md');
	});

	it('ingestionAPI.updatePinnedOrder posts order', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));

		await ingestionAPI.updatePinnedOrder(['file-1', 'file-2']);

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/files/pinned-order',
			expect.objectContaining({ method: 'PATCH' })
		);
	});

	it('tasksAPI.counts falls back on 404', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(
			Promise.resolve({
				ok: false,
				status: 404
			} as Response)
		);

		const data = await tasksAPI.counts();

		expect(data.counts.today).toBe(0);
		expect(data.groups).toEqual([]);
	});

	it('notesAPI.listTree returns children', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ children: [{ id: 'n1' }] }));

		const data = await notesAPI.listTree();

		expect(data.children).toHaveLength(1);
	});

	it('tasksAPI.search returns list data', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ tasks: [] }));

		const data = await tasksAPI.search('query');

		expect(data.tasks).toEqual([]);
	});

	it('tasksAPI.list returns list data', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ scope: 'today', tasks: [] }));

		const data = await tasksAPI.list('today');

		expect(data.scope).toBe('today');
	});

	it('tasksAPI.projectTasks returns list data', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ tasks: [{ id: 't1' }] }));

		const data = await tasksAPI.projectTasks('p1');

		expect(data.tasks?.[0].id).toBe('t1');
	});

	it('tasksAPI.createGroup posts group data', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'a1' }));

		await tasksAPI.createGroup('Home');

		const body = fetchSpy.mock.calls[0]?.[1]?.body;
		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/tasks/groups',
			expect.objectContaining({ method: 'POST' })
		);
		expect(JSON.parse(String(body))).toEqual({ title: 'Home' });
	});

	it('tasksAPI.createProject posts project data', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: 'p1' }));

		await tasksAPI.createProject('Launch', null);

		const body = fetchSpy.mock.calls[0]?.[1]?.body;
		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/tasks/projects',
			expect.objectContaining({ method: 'POST' })
		);
		expect(JSON.parse(String(body))).toEqual({ title: 'Launch', groupId: null });
	});

	it('ingestionAPI.delete ignores 404', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(
			Promise.resolve({ ok: false, status: 404 } as Response)
		);

		await expect(ingestionAPI.delete('file-1')).resolves.toBeUndefined();
	});

	it('notesAPI.updatePinnedOrder throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(notesAPI.updatePinnedOrder(['n1'])).rejects.toThrow(
			'Failed to update pinned order'
		);
	});

	it('websitesAPI.updatePinnedOrder throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(websitesAPI.updatePinnedOrder(['w1'])).rejects.toThrow(
			'Failed to update pinned order'
		);
	});

	it('tasksAPI.apply throws on failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(failJson());

		await expect(tasksAPI.apply({ op: 'noop' })).rejects.toThrow('Failed to apply task operation');
	});

	it('tasksAPI.sync posts operations', async () => {
		const fetchSpy = vi.spyOn(global, 'fetch').mockReturnValue(
			okJson({
				applied: [],
				tasks: [],
				nextTasks: [],
				conflicts: [],
				updates: { tasks: [], projects: [], groups: [] },
				serverUpdatedSince: '2026-01-22T10:00:00Z'
			})
		);

		const data = await tasksAPI.sync({ last_sync: null, operations: [{ op: 'noop' }] });

		expect(fetchSpy).toHaveBeenCalledWith(
			'/api/v1/tasks/sync',
			expect.objectContaining({ method: 'POST' })
		);
		expect(data.serverUpdatedSince).toBe('2026-01-22T10:00:00Z');
		const body = fetchSpy.mock.calls[0]?.[1]?.body;
		expect(JSON.parse(String(body)).operations[0].operation_id).toBeTruthy();
	});

	it('ingestionAPI.upload resolves with response payload', async () => {
		class MockXHR {
			upload = {
				addEventListener: vi.fn((event: string, cb: (event: ProgressEvent) => void) => {
					if (event === 'progress') {
						cb({
							lengthComputable: true,
							loaded: 50,
							total: 100
						} as ProgressEvent);
					}
				})
			};
			onload: (() => void) | null = null;
			onerror: (() => void) | null = null;
			responseText = JSON.stringify({ file_id: 'file-123' });
			status = 200;
			withCredentials = false;
			open = vi.fn();
			send = vi.fn(() => {
				this.onload?.();
			});
		}

		(global as any).XMLHttpRequest = MockXHR;

		const result = await ingestionAPI.upload(new File(['content'], 'test.txt'));

		expect(result.file_id).toBe('file-123');
	});
});
