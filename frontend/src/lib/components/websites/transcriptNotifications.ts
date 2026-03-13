import { toast } from 'svelte-sonner';

const TRANSCRIPT_FAILURE_TITLE = 'Transcript unavailable';
const TRANSCRIPT_FAILURE_DESCRIPTION = "Couldn't get the transcript right now. Please try again.";

export function showTranscriptFailureToast(): void {
	toast.error(TRANSCRIPT_FAILURE_TITLE, {
		description: TRANSCRIPT_FAILURE_DESCRIPTION
	});
}

export function handleTranscriptPollingError(resetPendingTranscript: () => void): void {
	resetPendingTranscript();
	showTranscriptFailureToast();
}
