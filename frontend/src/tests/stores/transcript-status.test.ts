import { beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { transcriptStatusStore } from '$lib/stores/transcript-status';

describe('transcriptStatusStore', () => {
	beforeEach(() => {
		transcriptStatusStore.set(null);
	});

	it('starts with null state', () => {
		expect(get(transcriptStatusStore)).toBe(null);
	});

	it('sets processing state', () => {
		transcriptStatusStore.set({
			status: 'processing',
			websiteId: 'site-1',
			videoId: 'video-1',
			fileId: 'file-1'
		});

		const state = get(transcriptStatusStore);
		expect(state).toEqual({
			status: 'processing',
			websiteId: 'site-1',
			videoId: 'video-1',
			fileId: 'file-1'
		});
	});

	it('clears state by setting null', () => {
		transcriptStatusStore.set({
			status: 'processing',
			websiteId: 'site-1',
			videoId: 'video-1',
			fileId: 'file-1'
		});

		transcriptStatusStore.set(null);
		expect(get(transcriptStatusStore)).toBe(null);
	});

	it('subscribes to changes', () => {
		const values: unknown[] = [];
		const unsubscribe = transcriptStatusStore.subscribe((value) => values.push(value));

		transcriptStatusStore.set({
			status: 'processing',
			websiteId: 'site-1',
			videoId: 'video-1',
			fileId: 'file-1'
		});
		transcriptStatusStore.set(null);

		unsubscribe();
		expect(values).toHaveLength(3);
		expect(values[0]).toBe(null);
		expect(values[1]).toEqual({
			status: 'processing',
			websiteId: 'site-1',
			videoId: 'video-1',
			fileId: 'file-1'
		});
		expect(values[2]).toBe(null);
	});
});
