import { describe, expect, it } from 'vitest';
import { isIPhoneUserAgent } from '$lib/utils/device';

describe('isIPhoneUserAgent', () => {
	it('returns true for iPhone user agents', () => {
		expect(
			isIPhoneUserAgent(
				'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1'
			)
		).toBe(true);
	});

	it('returns false for non-iPhone user agents', () => {
		expect(
			isIPhoneUserAgent(
				'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Mobile Safari/537.36'
			)
		).toBe(false);
		expect(
			isIPhoneUserAgent(
				'Mozilla/5.0 (iPad; CPU OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1'
			)
		).toBe(false);
		expect(
			isIPhoneUserAgent(
				'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36'
			)
		).toBe(false);
	});
});
