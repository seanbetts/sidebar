import { describe, expect, it } from 'vitest';
import {
	applyTranscriptQueuedState,
	resetTranscriptLinkState
} from '$lib/components/websites/transcriptLinkState';

describe('transcriptLinkState', () => {
	it('restores transcript link interactivity after queued state', () => {
		const link = document.createElement('a');
		link.textContent = 'Get Transcript';

		applyTranscriptQueuedState(link);
		expect(link.getAttribute('aria-disabled')).toBe('true');
		expect(link.classList.contains('transcript-queued')).toBe(true);
		expect(link.getAttribute('data-youtube-transcript-status')).toBe('queued');
		expect(link.textContent).toBe('Transcribing');

		resetTranscriptLinkState(link);
		expect(link.hasAttribute('aria-busy')).toBe(false);
		expect(link.hasAttribute('aria-disabled')).toBe(false);
		expect(link.classList.contains('transcript-queued')).toBe(false);
		expect(link.hasAttribute('data-youtube-transcript-status')).toBe(false);
		expect(link.textContent).toBe('Get Transcript');
	});
});
