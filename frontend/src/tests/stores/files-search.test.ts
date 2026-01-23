import { beforeEach, describe, expect, it } from 'vitest';
import { get } from 'svelte/store';
import { filesSearchStore } from '$lib/stores/files-search';

describe('filesSearchStore', () => {
	beforeEach(() => {
		filesSearchStore.clear();
	});

	it('starts with empty string', () => {
		expect(get(filesSearchStore)).toBe('');
	});

	it('sets search query', () => {
		filesSearchStore.set('test query');
		expect(get(filesSearchStore)).toBe('test query');
	});

	it('clears search query', () => {
		filesSearchStore.set('something');
		filesSearchStore.clear();
		expect(get(filesSearchStore)).toBe('');
	});

	it('subscribes to changes', () => {
		const values: string[] = [];
		const unsubscribe = filesSearchStore.subscribe((value) => values.push(value));

		filesSearchStore.set('first');
		filesSearchStore.set('second');
		filesSearchStore.clear();

		unsubscribe();
		expect(values).toEqual(['', 'first', 'second', '']);
	});
});
