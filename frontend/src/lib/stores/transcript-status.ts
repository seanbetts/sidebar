import { writable } from 'svelte/store';

export type TranscriptJobState = {
	status: 'processing';
	websiteId: string;
	videoId: string;
	fileId: string;
} | null;

export const transcriptStatusStore = writable<TranscriptJobState>(null);
