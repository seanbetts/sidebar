export function applyTranscriptQueuedState(link: HTMLAnchorElement): void {
	link.setAttribute('aria-busy', 'true');
	link.setAttribute('aria-disabled', 'true');
	link.classList.add('transcript-queued');
	link.setAttribute('data-youtube-transcript-status', 'queued');
	link.textContent = 'Transcribing';
}

export function resetTranscriptLinkState(link: HTMLAnchorElement): void {
	link.removeAttribute('aria-busy');
	link.removeAttribute('aria-disabled');
	link.classList.remove('transcript-queued');
	link.removeAttribute('data-youtube-transcript-status');
	link.textContent = 'Get Transcript';
}
