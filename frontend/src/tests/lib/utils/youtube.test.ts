import { describe, expect, it } from 'vitest';
import {
	buildYouTubeNoCookieEmbedUrl,
	extractYouTubeVideoId,
	isYouTubeHost
} from '$lib/utils/youtube';

describe('youtube utils', () => {
	it('matches only valid youtube hosts', () => {
		expect(isYouTubeHost('youtube.com')).toBe(true);
		expect(isYouTubeHost('www.youtube.com')).toBe(true);
		expect(isYouTubeHost('m.youtube.com')).toBe(true);
		expect(isYouTubeHost('youtu.be')).toBe(true);
		expect(isYouTubeHost('www.youtu.be')).toBe(true);
		expect(isYouTubeHost('notyoutube.com')).toBe(false);
		expect(isYouTubeHost('youtube.com.evil.com')).toBe(false);
	});

	it('extracts video ids from supported youtube url forms', () => {
		expect(extractYouTubeVideoId('https://youtu.be/abc123xyzAA?t=10')).toBe('abc123xyzAA');
		expect(extractYouTubeVideoId('https://www.youtube.com/watch?v=abc123xyzAA')).toBe(
			'abc123xyzAA'
		);
		expect(extractYouTubeVideoId('https://www.youtube.com/shorts/abc123xyzAA')).toBe('abc123xyzAA');
		expect(extractYouTubeVideoId('https://www.youtube.com/embed/abc123xyzAA')).toBe('abc123xyzAA');
	});

	it('rejects non-youtube and invalid ids', () => {
		expect(extractYouTubeVideoId('https://example.com/watch?v=abc123xyzAA')).toBeNull();
		expect(extractYouTubeVideoId('https://www.youtube.com/watch?v=a')).toBeNull();
		expect(extractYouTubeVideoId('notaurl')).toBeNull();
	});

	it('builds no-cookie embed urls', () => {
		expect(buildYouTubeNoCookieEmbedUrl('https://www.youtube.com/watch?v=abc123xyzAA')).toBe(
			'https://www.youtube-nocookie.com/embed/abc123xyzAA'
		);
		expect(buildYouTubeNoCookieEmbedUrl('https://example.com/video')).toBeNull();
	});
});
