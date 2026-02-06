import { describe, expect, it } from 'vitest';
import {
	extractBaseDomain,
	formatWebsiteSubtitle,
	getWebsiteDisplayTitle,
	getWebsiteSourceUrl,
	stripWebsiteFrontmatter
} from '$lib/utils/websites';

describe('website utils', () => {
	it('falls back to url when title is empty', () => {
		expect(getWebsiteDisplayTitle({ title: '  ', url: 'https://example.com' })).toBe(
			'https://example.com'
		);
	});

	it('extracts base domain for country-code second-level domains', () => {
		expect(extractBaseDomain('www.docs.gov.uk')).toBe('docs.gov.uk');
		expect(extractBaseDomain('www.news.bbc.co.uk')).toBe('bbc.co.uk');
	});

	it('formats subtitle with reading time when present', () => {
		expect(formatWebsiteSubtitle('www.example.com', '5 mins')).toBe('example.com | 5 mins');
		expect(formatWebsiteSubtitle('www.example.com', null)).toBe('example.com');
	});

	it('prefers url_full for source links', () => {
		expect(
			getWebsiteSourceUrl({
				url: 'https://short.example.com',
				url_full: 'https://full.example.com/path'
			})
		).toBe('https://full.example.com/path');
	});

	it('strips frontmatter blocks when present', () => {
		const text = ['---', 'title: Example', '---', '', 'Body content'].join('\n');
		expect(stripWebsiteFrontmatter(text)).toBe('Body content');
	});
});
