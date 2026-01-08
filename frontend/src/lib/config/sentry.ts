import { browser } from '$app/environment';
import type { BrowserOptions } from '@sentry/browser';
import * as Sentry from '@sentry/sveltekit';
import { getPublicEnv } from '$lib/utils/publicEnv';

type SentryContext = Record<string, unknown>;

const publicEnv = getPublicEnv();
const sentryDsn = publicEnv.PUBLIC_SENTRY_DSN_FRONTEND ?? '';
const sentryEnvironment = publicEnv.PUBLIC_SENTRY_ENVIRONMENT || 'production';
const sentrySampleRate = parseSampleRate(publicEnv.PUBLIC_SENTRY_SAMPLE_RATE, 1);

let sentryInitialized = false;

function parseSampleRate(value: string | undefined, fallback: number): number {
	if (!value) return fallback;
	const parsed = Number(value);
	if (!Number.isFinite(parsed)) return fallback;
	return Math.min(1, Math.max(0, parsed));
}

const sanitizeEvent: NonNullable<BrowserOptions['beforeSend']> = (event, _hint) => {
	const request = event.request ? { ...event.request } : undefined;
	if (request?.headers && typeof request.headers === 'object') {
		const headers = { ...request.headers } as Record<string, string>;
		delete headers.authorization;
		delete headers.cookie;
		request.headers = headers;
	}

	if (request?.url) {
		request.url = request.url.split('?')[0];
	}
	if (request?.data) {
		request.data = '[Filtered]';
	}

	const breadcrumbs = event.breadcrumbs?.map((breadcrumb) => ({
		...breadcrumb,
		data: undefined
	}));

	return {
		...event,
		request,
		user: undefined,
		breadcrumbs
	};
};

function initSentrySdk(): void {
	if (sentryInitialized || !sentryDsn) return;

	Sentry.init({
		dsn: sentryDsn,
		environment: sentryEnvironment,
		sampleRate: sentrySampleRate,
		tracesSampleRate: sentrySampleRate,
		beforeSend: sanitizeEvent
	});

	sentryInitialized = true;
}

/**
 * Initialize Sentry for browser execution.
 */
export function initSentryClient(): void {
	if (!browser) return;
	initSentrySdk();
}

/**
 * Initialize Sentry for server execution.
 */
export function initSentryServer(): void {
	if (browser) return;
	initSentrySdk();
}

/**
 * Capture an error in Sentry when configured.
 *
 * @param error Error instance or payload.
 * @param context Extra context to attach.
 */
export function captureError(error: unknown, context?: SentryContext): void {
	if (!sentryInitialized) return;

	Sentry.withScope((scope) => {
		if (context) {
			scope.setContext('context', context);
		}

		if (error instanceof Error) {
			Sentry.captureException(error);
		} else {
			Sentry.captureMessage(String(error));
		}
	});
}
