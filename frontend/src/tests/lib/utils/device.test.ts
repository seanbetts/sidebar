import { describe, expect, it } from 'vitest';
import { isIPhoneDevice } from '$lib/utils/device';

describe('device utils', () => {
	it('detects iPhone user agents', () => {
		expect(
			isIPhoneDevice('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15')
		).toBe(true);
	});

	it('does not detect non-iPhone user agents', () => {
		expect(
			isIPhoneDevice(
				'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 Chrome/120.0.0.0'
			)
		).toBe(false);
	});
});
