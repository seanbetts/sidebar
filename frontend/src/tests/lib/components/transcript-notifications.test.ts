import { describe, expect, it, vi } from 'vitest';
import {
	handleTranscriptPollingError,
	showTranscriptFailureToast
} from '$lib/components/websites/transcriptNotifications';

const { toast } = vi.hoisted(() => ({
	toast: {
		error: vi.fn()
	}
}));

vi.mock('svelte-sonner', () => ({ toast }));

describe('transcriptNotifications', () => {
	it('shows a friendly transcript failure toast', () => {
		showTranscriptFailureToast();

		expect(toast.error).toHaveBeenCalledWith('Transcript unavailable', {
			description: "Couldn't get the transcript right now. Please try again."
		});
	});

	it('clears pending transcript state when polling fails', () => {
		const resetPendingTranscript = vi.fn();

		handleTranscriptPollingError(resetPendingTranscript);

		expect(resetPendingTranscript).toHaveBeenCalledTimes(1);
		expect(toast.error).toHaveBeenCalledWith('Transcript unavailable', {
			description: "Couldn't get the transcript right now. Please try again."
		});
	});
});
