import { describe, expect, it } from 'vitest';
import { rewriteVideoEmbeds } from '$lib/components/websites/viewerEmbedTransforms';

describe('viewerEmbedTransforms', () => {
	it('removes transcript marker and legacy transcript title from rendered markdown', () => {
		const input = [
			'___',
			'',
			'<!-- YOUTUBE_TRANSCRIPT:dQw4w9WgXcQ -->',
			'',
			'### Transcript of Example video',
			'',
			'Hello transcript'
		].join('\n');

		const output = rewriteVideoEmbeds(input, null, null);

		expect(output).toContain('___');
		expect(output).toContain('Hello transcript');
		expect(output).not.toContain('YOUTUBE_TRANSCRIPT');
		expect(output).not.toContain('Transcript of Example video');
	});
});
