import { describe, expect, it, vi, afterEach } from 'vitest';
import { memoriesAPI } from '$lib/services/memories';

const okJson = (value: unknown) =>
	Promise.resolve({
		ok: true,
		json: async () => value
	} as Response);

const fail = (status = 500) =>
	Promise.resolve({
		ok: false,
		status
	} as Response);

describe('MemoriesAPI', () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it('lists memories', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson([{ id: '1' }]));
		const data = await memoriesAPI.list();
		expect(data).toEqual([{ id: '1' }]);
	});

	it('throws on list failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(fail());
		await expect(memoriesAPI.list()).rejects.toThrow('Failed to list memories');
	});

	it('gets a memory by id', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: '1' }));
		const data = await memoriesAPI.get('1');
		expect(data).toEqual({ id: '1' });
	});

	it('throws on get failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(fail());
		await expect(memoriesAPI.get('1')).rejects.toThrow('Failed to get memory');
	});

	it('creates memories', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: '2' }));
		const data = await memoriesAPI.create({ path: 'p', content: 'c' });
		expect(data.id).toBe('2');
	});

	it('throws on create failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(fail());
		await expect(memoriesAPI.create({ path: 'p', content: 'c' })).rejects.toThrow(
			'Failed to create memory'
		);
	});

	it('updates a memory', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({ id: '1', content: 'new content' }));
		const data = await memoriesAPI.update('1', { content: 'new content' });
		expect(data).toEqual({ id: '1', content: 'new content' });
	});

	it('throws on update failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(fail());
		await expect(memoriesAPI.update('1', { content: 'new content' })).rejects.toThrow(
			'Failed to update memory'
		);
	});

	it('deletes memory when request succeeds', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(okJson({}));
		await expect(memoriesAPI.delete('1')).resolves.toBeUndefined();
	});

	it('throws on delete failure', async () => {
		vi.spyOn(global, 'fetch').mockReturnValue(fail());
		await expect(memoriesAPI.delete('1')).rejects.toThrow('Failed to delete memory');
	});
});
