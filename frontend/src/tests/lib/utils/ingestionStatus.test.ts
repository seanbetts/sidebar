import { describe, expect, it } from 'vitest';
import { buildIngestionStatusMessage, hasReadyTransition } from '$lib/utils/ingestionStatus';

describe('ingestion status utils', () => {
	it('does not report ready transition for first-seen ready status', () => {
		expect(hasReadyTransition(undefined, 'ready')).toBe(false);
	});

	it('reports ready transition when status changes to ready', () => {
		expect(hasReadyTransition('processing', 'ready')).toBe(true);
		expect(hasReadyTransition('failed', 'ready')).toBe(true);
	});

	it('does not report ready transition when status is unchanged', () => {
		expect(hasReadyTransition('ready', 'ready')).toBe(false);
	});

	it('uses user message before derived stage label', () => {
		expect(
			buildIngestionStatusMessage({
				status: 'processing',
				stage: 'extracting',
				user_message: 'Extracting text 42%'
			})
		).toBe('Extracting text 42%');
	});
});
