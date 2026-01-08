import { beforeEach, describe, expect, it, vi } from 'vitest';

const onCLS = vi.fn();
const onFCP = vi.fn();
const onINP = vi.fn();
const onLCP = vi.fn();
const onTTFB = vi.fn();

vi.mock('web-vitals', () => ({
	onCLS,
	onFCP,
	onINP,
	onLCP,
	onTTFB
}));

vi.mock('$app/environment', () => ({
	browser: true
}));

describe('initWebVitals', () => {
	beforeEach(() => {
		vi.resetModules();
		onCLS.mockClear();
		onFCP.mockClear();
		onINP.mockClear();
		onLCP.mockClear();
		onTTFB.mockClear();
	});

	it('skips initialization when disabled', async () => {
		vi.doMock('$lib/utils/publicEnv', () => ({
			getPublicEnv: () => ({
				PUBLIC_ENABLE_WEB_VITALS: 'false',
				PUBLIC_WEB_VITALS_SAMPLE_RATE: '1',
				PUBLIC_METRICS_ENDPOINT: ''
			})
		}));

		const { initWebVitals } = await import('$lib/utils/performance');
		await initWebVitals(() => '/');

		expect(onCLS).not.toHaveBeenCalled();
		expect(onFCP).not.toHaveBeenCalled();
		expect(onINP).not.toHaveBeenCalled();
		expect(onLCP).not.toHaveBeenCalled();
		expect(onTTFB).not.toHaveBeenCalled();
	});

	it('registers vitals when enabled', async () => {
		vi.doMock('$lib/utils/publicEnv', () => ({
			getPublicEnv: () => ({
				PUBLIC_ENABLE_WEB_VITALS: 'true',
				PUBLIC_WEB_VITALS_SAMPLE_RATE: '1',
				PUBLIC_METRICS_ENDPOINT: ''
			})
		}));

		const { initWebVitals } = await import('$lib/utils/performance');
		await initWebVitals(() => '/');

		expect(onCLS).toHaveBeenCalledTimes(1);
		expect(onFCP).toHaveBeenCalledTimes(1);
		expect(onINP).toHaveBeenCalledTimes(1);
		expect(onLCP).toHaveBeenCalledTimes(1);
		expect(onTTFB).toHaveBeenCalledTimes(1);
	});
});
