import { beforeEach, describe, expect, it, vi } from 'vitest';

const init = vi.fn();

vi.mock('@sentry/sveltekit', () => ({
	init
}));

vi.mock('$app/environment', () => ({
	browser: true
}));

describe('initSentryClient', () => {
	beforeEach(() => {
		vi.resetModules();
		init.mockClear();
	});

	it('skips initialization without a DSN', async () => {
		vi.doMock('$lib/utils/publicEnv', () => ({
			getPublicEnv: () => ({
				PUBLIC_SENTRY_DSN_FRONTEND: '',
				PUBLIC_SENTRY_ENVIRONMENT: 'test',
				PUBLIC_SENTRY_SAMPLE_RATE: '0.1'
			})
		}));

		const { initSentryClient } = await import('$lib/config/sentry');
		initSentryClient();

		expect(init).not.toHaveBeenCalled();
	});

	it('initializes when DSN is present', async () => {
		vi.doMock('$lib/utils/publicEnv', () => ({
			getPublicEnv: () => ({
				PUBLIC_SENTRY_DSN_FRONTEND: 'https://example@sentry.io/123',
				PUBLIC_SENTRY_ENVIRONMENT: 'test',
				PUBLIC_SENTRY_SAMPLE_RATE: '0.1'
			})
		}));

		const { initSentryClient } = await import('$lib/config/sentry');
		initSentryClient();

		expect(init).toHaveBeenCalledTimes(1);
	});
});
